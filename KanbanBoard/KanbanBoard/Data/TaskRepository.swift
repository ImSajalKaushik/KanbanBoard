//
//  TaskRepository.swift
//  KanbanBoard
//
//  Created by Sajal Kaushik on 04/09/26.
//

import Foundation

extension TaskRepository {
    /// Builds the production repository and keeps storage and sync implementation details outside the UI layer.
    static func makeDefault() throws -> TaskRepository {
        let persistenceController = try PersistenceController()
        let store = CoreDataTaskStore(context: persistenceController.newBackgroundContext())
        let syncController = TaskSyncService(
            localStore: store,
            remoteAPI: FirestoreTaskAPI(),
            networkMonitor: NWPathNetworkMonitor.shared
        )
        return TaskRepository(
            localStore: store,
            persistenceController: persistenceController,
            syncController: syncController
        )
    }
}

enum TaskRepositoryError: LocalizedError, Equatable {
    case emptyTitle

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            "A task title is required."
        }
    }
}

@MainActor
final class TaskRepository {
    private let localStore: any LocalTaskStore
    private let syncTrigger: (any TaskSyncTriggering)?
    private let persistenceController: PersistenceController?
    private let syncController: (any TaskSyncControlling)?
    // server time at later point
    private let now: () -> Date
    private var hasLoaded = false

    var onTasksChanged: (@MainActor () -> Void)? {
        didSet {
            syncController?.onTasksChanged = onTasksChanged
        }
    }

    init(localStore: any LocalTaskStore,
         syncTrigger: (any TaskSyncTriggering)? = nil,
         persistenceController: PersistenceController? = nil,
         syncController: (any TaskSyncControlling)? = nil,
         now: @escaping () -> Date = Date.init) {
        self.localStore = localStore
        self.syncTrigger = syncController ?? syncTrigger
        self.persistenceController = persistenceController
        self.syncController = syncController
        self.now = now
    }

    func load() async throws {
        guard !hasLoaded else { return }
        if let persistenceController {
            try await persistenceController.load()
        }
        hasLoaded = true
    }

    func startSync() {
        syncController?.start()
    }

    func requestSync() {
        syncController?.requestSync()
    }

    func stopSync() {
        syncController?.stop()
    }

    func fetchTasks() async throws -> [BoardTask] {
        try await localStore.fetchTasks()
    }

    func createTask(title: String,
                    details: String,
                    status: TaskStatus = .todo) async throws -> BoardTask {
        let task = try await localStore.createTask(
            title: try validatedTitle(title),
            details: details.trimmingCharacters(in: .whitespacesAndNewlines),
            status: status,
            createdAt: now()
        )
        syncTrigger?.requestSync()
        return task
    }

    func updateTask(id: String,
                    title: String,
                    details: String,
                    status: TaskStatus) async throws -> BoardTask {
        let task = try await localStore.updateTask(
            id: id,
            title: try validatedTitle(title),
            details: details.trimmingCharacters(in: .whitespacesAndNewlines),
            status: status,
            updatedAt: now()
        )
        syncTrigger?.requestSync()
        return task
    }

    func deleteTask(id: String) async throws {
        try await localStore.deleteTask(id: id, deletedAt: now())
        syncTrigger?.requestSync()
    }

    func moveTask(id: String,
                  to status: TaskStatus,
                  destinationIndex: Int? = nil) async throws -> BoardTask {
        let task = try await localStore.moveTask(
            id: id,
            to: status,
            destinationIndex: destinationIndex,
            updatedAt: now()
        )
        syncTrigger?.requestSync()
        return task
    }

    private func validatedTitle(_ title: String) throws -> String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw TaskRepositoryError.emptyTitle
        }
        return title
    }
}
