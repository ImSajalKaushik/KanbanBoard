//
//  CoreDataTaskStore.swift
//  KanbanBoard
//
//  Created by Sajal Kaushik on 04/09/26.
//

import CoreData

enum LocalTaskStoreError: LocalizedError {
    case corruptRecord(String)
    case duplicateTask(String)
    case invalidModel
    case taskNotFound(String)

    var errorDescription: String? {
        switch self {
        case .corruptRecord(let id):
            "Task \(id) contains unsupported persisted values."
        case .duplicateTask(let id):
            "Task \(id) already exists."
        case .invalidModel:
            "The Core Data task entity is not configured correctly."
        case .taskNotFound(let id):
            "Task \(id) could not be found."
        }
    }
}

@MainActor
final class CoreDataTaskStore: LocalTaskStore, LocalTaskSyncStore {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func fetchTasks() async throws -> [BoardTask] {
        try await context.perform { [context] in
            let request = TaskRecord.fetchRequest()
            request.predicate = NSPredicate(format: "\(#keyPath(TaskRecord.isTombstone)) == NO")
            request.sortDescriptors = [
                NSSortDescriptor(key: #keyPath(TaskRecord.statusRaw), ascending: true),
                NSSortDescriptor(key: #keyPath(TaskRecord.sortIndex), ascending: true),
                NSSortDescriptor(key: #keyPath(TaskRecord.createdAt), ascending: true)
            ]

            return try context.fetch(request)
                .map { try Self.makeTask(from: $0) }
                .sorted(by: Self.areInBoardOrder)
        }
    }

    func createTask(title: String,
                    details: String,
                    status: TaskStatus,
                    createdAt: Date) async throws -> BoardTask {
        try await context.perform { [context] in
            let id = UUID().uuidString
            guard try Self.fetchRecord(id: id, in: context) == nil else {
                throw LocalTaskStoreError.duplicateTask(id)
            }

            let sortIndex = try Self.nextSortIndex(for: status, in: context)
            guard let record = NSEntityDescription.insertNewObject(
                forEntityName: "TaskRecord",
                into: context
            ) as? TaskRecord else {
                throw LocalTaskStoreError.invalidModel
            }
            record.id = id
            record.title = title
            record.details = details
            record.statusRaw = status.rawValue
            record.sortIndex = sortIndex
            record.createdAt = createdAt
            record.updatedAt = createdAt
            record.syncStateRaw = TaskSyncState.pending.rawValue
            record.isTombstone = false
            record.lastSyncError = nil

            try context.save()
            return try Self.makeTask(from: record)
        }
    }

    func updateTask(id: String,
                    title: String,
                    details: String,
                    status: TaskStatus,
                    updatedAt: Date) async throws -> BoardTask {
        try await context.perform { [context] in
            guard let record = try Self.fetchRecord(id: id, in: context) else {
                throw LocalTaskStoreError.taskNotFound(id)
            }

            let previousStatus = try Self.status(for: record)
            if previousStatus != status {
                let sortIndex = try Self.nextSortIndex(for: status, in: context)
                record.statusRaw = status.rawValue
                record.sortIndex = sortIndex
                try Self.compactIndices(in: previousStatus, updatedAt: updatedAt, context: context)
            }

            record.title = title
            record.details = details
            Self.markPending(record, updatedAt: updatedAt)

            try context.save()
            return try Self.makeTask(from: record)
        }
    }

    func deleteTask(id: String, deletedAt: Date) async throws {
        try await context.perform { [context] in
            guard let record = try Self.fetchRecord(id: id, in: context) else {
                throw LocalTaskStoreError.taskNotFound(id)
            }

            let status = try Self.status(for: record)
            record.isTombstone = true
            Self.markPending(record, updatedAt: deletedAt)
            try Self.compactIndices(in: status, updatedAt: deletedAt, context: context)
            try context.save()
        }
    }

    func moveTask(id: String,
                  to status: TaskStatus,
                  destinationIndex: Int?,
                  updatedAt: Date) async throws -> BoardTask {
        try await context.perform { [context] in
            guard let record = try Self.fetchRecord(id: id, in: context) else {
                throw LocalTaskStoreError.taskNotFound(id)
            }

            let previousStatus = try Self.status(for: record)
            record.statusRaw = status.rawValue
            Self.markPending(record, updatedAt: updatedAt)

            if previousStatus != status {
                try Self.compactIndices(in: previousStatus, updatedAt: updatedAt, context: context)
            }

            var destinationRecords = try Self.fetchRecords(for: status, in: context)
                .filter { $0.id != id }
            let index = min(max(destinationIndex ?? destinationRecords.count, 0), destinationRecords.count)
            destinationRecords.insert(record, at: index)
            Self.applyOrder(destinationRecords, updatedAt: updatedAt)

            try context.save()
            return try Self.makeTask(from: record)
        }
    }

    func fetchPendingSyncTasks() async throws -> [TaskSyncPayload] {
        try await context.perform { [context] in
            let request = TaskRecord.fetchRequest()
            request.predicate = NSPredicate(
                format: "\(#keyPath(TaskRecord.syncStateRaw)) IN %@",
                [TaskSyncState.pending.rawValue, TaskSyncState.failed.rawValue]
            )
            request.sortDescriptors = [
                NSSortDescriptor(key: #keyPath(TaskRecord.updatedAt), ascending: true),
                NSSortDescriptor(key: #keyPath(TaskRecord.createdAt), ascending: true)
            ]
            return try context.fetch(request).map(Self.makeSyncPayload)
        }
    }

    func reconcileRemoteTasks(_ tasks: [TaskSyncPayload],
                              removeMissingSyncedTasks: Bool) async throws -> Bool {
        try await context.perform { [context] in
            var didChange = false
            let remoteIDs = Set(tasks.map(\.id))

            for task in tasks {
                guard let record = try Self.fetchAnyRecord(id: task.id, in: context) else {
                    try Self.insertRemoteTask(task, in: context)
                    didChange = true
                    continue
                }

                let localTask = try Self.makeSyncPayload(from: record)
                if Self.areEquivalentAcrossTimestampPrecision(task, localTask) {
                    didChange = Self.markSynced(record) || didChange
                    continue
                }

                if Self.isMeaningfullyOlder(task.updatedAt, than: localTask.updatedAt) {
                    if record.syncStateRaw == TaskSyncState.synced.rawValue {
                        record.syncStateRaw = TaskSyncState.pending.rawValue
                        record.lastSyncError = nil
                        didChange = true
                    }
                    continue
                }

                Self.applyRemoteTask(task, to: record)
                didChange = true
            }

            if removeMissingSyncedTasks {
                for record in try Self.fetchAllRecords(in: context)
                where !remoteIDs.contains(record.id)
                    && record.syncStateRaw == TaskSyncState.synced.rawValue {
                    context.delete(record)
                    didChange = true
                }
            }

            if context.hasChanges {
                try context.save()
            }
            return didChange
        }
    }

    func markTaskSynced(id: String, expectedUpdatedAt: Date) async throws -> Bool {
        try await context.perform { [context] in
            guard let record = try Self.fetchAnyRecord(id: id, in: context),
                  record.updatedAt == expectedUpdatedAt else {
                return false
            }

            let didChange = Self.markSynced(record)
            if context.hasChanges {
                try context.save()
            }
            return didChange
        }
    }

    func markTaskFailed(id: String,
                        expectedUpdatedAt: Date,
                        message: String) async throws -> Bool {
        try await context.perform { [context] in
            guard let record = try Self.fetchAnyRecord(id: id, in: context),
                  record.updatedAt == expectedUpdatedAt else {
                return false
            }

            let didChange = record.syncStateRaw != TaskSyncState.failed.rawValue
                || record.lastSyncError != message
            record.syncStateRaw = TaskSyncState.failed.rawValue
            record.lastSyncError = message
            if context.hasChanges {
                try context.save()
            }
            return didChange
        }
    }

    nonisolated private static func fetchRecord(id: String,
                                                in context: NSManagedObjectContext) throws -> TaskRecord? {
        let request = TaskRecord.fetchRequest()
        request.predicate = NSPredicate(
            format: "\(#keyPath(TaskRecord.id)) == %@ AND \(#keyPath(TaskRecord.isTombstone)) == NO",
            id
        )
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    nonisolated private static func fetchAnyRecord(
        id: String,
        in context: NSManagedObjectContext
    ) throws -> TaskRecord? {
        let request = TaskRecord.fetchRequest()
        request.predicate = NSPredicate(format: "\(#keyPath(TaskRecord.id)) == %@", id)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    nonisolated private static func fetchAllRecords(
        in context: NSManagedObjectContext
    ) throws -> [TaskRecord] {
        try context.fetch(TaskRecord.fetchRequest())
    }

    nonisolated private static func fetchRecords(for status: TaskStatus,
                                                 in context: NSManagedObjectContext) throws -> [TaskRecord] {
        let request = TaskRecord.fetchRequest()
        request.predicate = NSPredicate(
            format: "\(#keyPath(TaskRecord.statusRaw)) == %@ AND \(#keyPath(TaskRecord.isTombstone)) == NO",
            status.rawValue
        )
        request.sortDescriptors = [
            NSSortDescriptor(key: #keyPath(TaskRecord.sortIndex), ascending: true),
            NSSortDescriptor(key: #keyPath(TaskRecord.createdAt), ascending: true)
        ]
        return try context.fetch(request)
    }

    nonisolated private static func nextSortIndex(for status: TaskStatus,
                                                  in context: NSManagedObjectContext) throws -> Int64 {
        (try fetchRecords(for: status, in: context).last?.sortIndex ?? -1) + 1
    }

    nonisolated private static func compactIndices(in status: TaskStatus,
                                                   updatedAt: Date,
                                                   context: NSManagedObjectContext) throws {
        applyOrder(try fetchRecords(for: status, in: context), updatedAt: updatedAt)
    }

    nonisolated private static func applyOrder(_ records: [TaskRecord], updatedAt: Date) {
        for (index, record) in records.enumerated() where record.sortIndex != Int64(index) {
            record.sortIndex = Int64(index)
            markPending(record, updatedAt: updatedAt)
        }
    }

    nonisolated private static func markPending(_ record: TaskRecord, updatedAt: Date) {
        record.updatedAt = updatedAt
        record.syncStateRaw = TaskSyncState.pending.rawValue
        record.lastSyncError = nil
    }

    nonisolated private static func markSynced(_ record: TaskRecord) -> Bool {
        let didChange = record.syncStateRaw != TaskSyncState.synced.rawValue
            || record.lastSyncError != nil
        record.syncStateRaw = TaskSyncState.synced.rawValue
        record.lastSyncError = nil
        return didChange
    }

    nonisolated private static func areEquivalentAcrossTimestampPrecision(
        _ lhs: TaskSyncPayload,
        _ rhs: TaskSyncPayload
    ) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.details == rhs.details
            && lhs.status == rhs.status
            && lhs.sortIndex == rhs.sortIndex
            && abs(lhs.createdAt.timeIntervalSince(rhs.createdAt)) <= timestampTolerance
            && abs(lhs.updatedAt.timeIntervalSince(rhs.updatedAt)) <= timestampTolerance
            && lhs.isDeleted == rhs.isDeleted
    }

    /// Timestamps within tolerance are treated as the same edit because Firestore round trips lose sub-millisecond precision.
    /// Server clock would avoid such issues.
    nonisolated private static func isMeaningfullyOlder(_ lhs: Date, than rhs: Date) -> Bool {
        rhs.timeIntervalSince(lhs) > timestampTolerance
    }

    nonisolated private static let timestampTolerance: TimeInterval = 0.001

    nonisolated private static func insertRemoteTask(
        _ task: TaskSyncPayload,
        in context: NSManagedObjectContext
    ) throws {
        guard let record = NSEntityDescription.insertNewObject(
            forEntityName: "TaskRecord",
            into: context
        ) as? TaskRecord else {
            throw LocalTaskStoreError.invalidModel
        }
        record.id = task.id
        applyRemoteTask(task, to: record)
    }

    nonisolated private static func applyRemoteTask(
        _ task: TaskSyncPayload,
        to record: TaskRecord
    ) {
        record.id = task.id
        record.title = task.title
        record.details = task.details
        record.statusRaw = task.status.rawValue
        record.sortIndex = task.sortIndex
        record.createdAt = task.createdAt
        record.updatedAt = task.updatedAt
        record.isTombstone = task.isDeleted
        record.syncStateRaw = TaskSyncState.synced.rawValue
        record.lastSyncError = nil
    }

    nonisolated private static func status(for record: TaskRecord) throws -> TaskStatus {
        guard let status = TaskStatus(rawValue: record.statusRaw) else {
            throw LocalTaskStoreError.corruptRecord(record.id)
        }
        return status
    }

    nonisolated private static func makeTask(from record: TaskRecord) throws -> BoardTask {
        guard let syncState = TaskSyncState(rawValue: record.syncStateRaw) else {
            throw LocalTaskStoreError.corruptRecord(record.id)
        }

        return BoardTask(
            id: record.id,
            title: record.title,
            details: record.details,
            status: try status(for: record),
            sortIndex: record.sortIndex,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            syncState: syncState,
            lastSyncError: record.lastSyncError
        )
    }

    nonisolated private static func makeSyncPayload(from record: TaskRecord) throws -> TaskSyncPayload {
        TaskSyncPayload(
            id: record.id,
            title: record.title,
            details: record.details,
            status: try status(for: record),
            sortIndex: record.sortIndex,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            isDeleted: record.isTombstone
        )
    }

    nonisolated private static func areInBoardOrder(_ lhs: BoardTask, _ rhs: BoardTask) -> Bool {
        if lhs.status != rhs.status {
            return lhs.status.sortOrder < rhs.status.sortOrder
        }
        if lhs.sortIndex != rhs.sortIndex {
            return lhs.sortIndex < rhs.sortIndex
        }
        return lhs.createdAt < rhs.createdAt
    }
}
