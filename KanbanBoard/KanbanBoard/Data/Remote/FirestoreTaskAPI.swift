//
//  FirestoreTaskAPI.swift
//  KanbanBoard
//
//  Created by Sajal Kaushik on 04/09/26.
//

import FirebaseFirestore
import Foundation

enum FirestoreTaskAPIError: LocalizedError, Equatable {
    case listenerEndedWithoutResult

    var errorDescription: String? {
        switch self {
        case .listenerEndedWithoutResult:
            "The Firestore task listener ended without a snapshot or error."
        }
    }
}

@MainActor
final class FirestoreTaskAPI: TaskAPI {
    private let collection: CollectionReference

    init(database: Firestore = Firestore.firestore(), collectionPath: String = "tasks") {
        collection = database.collection(collectionPath)
    }

    func fetchTasks() async throws -> [TaskSyncPayload] {
        let snapshot = try await collection.getDocuments()
        return snapshot.documents
            .compactMap(TaskSyncPayload.init(document:))
            .sorted(by: Self.areInBoardOrder)
    }

    func fetchTask(id: String) async throws -> TaskSyncPayload? {
        let snapshot = try await document(for: id).getDocument()
        guard snapshot.exists else { return nil }
        return TaskSyncPayload(document: snapshot)
    }

    func upsertTask(_ task: TaskSyncPayload) async throws {
        try await document(for: task.id).setData(Self.data(for: task))
    }

    func observeTasks() -> AsyncThrowingStream<RemoteTaskSnapshot, Error> {
        AsyncThrowingStream<RemoteTaskSnapshot, Error> { continuation in
            let registration = collection.addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
                if let error {
                    continuation.finish(throwing: RemoteTaskObservationError.failure(error.localizedDescription))
                    return
                }
                guard let snapshot else {
                    continuation.finish(throwing: RemoteTaskObservationError.listenerEndedWithoutResult)
                    return
                }

                let tasks = snapshot.documents
                    .compactMap(TaskSyncPayload.init(document:))
                    .sorted(by: Self.areInBoardOrder)
                continuation.yield(RemoteTaskSnapshot(
                    tasks: tasks,
                    isFromCache: snapshot.metadata.isFromCache,
                    hasPendingWrites: snapshot.metadata.hasPendingWrites
                ))
            }
            continuation.onTermination = { _ in
                registration.remove()
            }
        }
    }

    private func document(for id: String) -> DocumentReference {
        collection.document(id)
    }

    private static func data(for task: TaskSyncPayload) -> [String: Any] {
        [
            TaskSyncPayload.CodingKeys.title.rawValue: task.title,
            TaskSyncPayload.CodingKeys.details.rawValue: task.details,
            TaskSyncPayload.CodingKeys.status.rawValue: task.status.rawValue,
            TaskSyncPayload.CodingKeys.sortIndex.rawValue: task.sortIndex,
            TaskSyncPayload.CodingKeys.createdAt.rawValue: Timestamp(date: task.createdAt),
            TaskSyncPayload.CodingKeys.updatedAt.rawValue: Timestamp(date: task.updatedAt),
            TaskSyncPayload.CodingKeys.isDeleted.rawValue: task.isDeleted
        ]
    }

    private static func areInBoardOrder(_ lhs: TaskSyncPayload, _ rhs: TaskSyncPayload) -> Bool {
        if lhs.status != rhs.status {
            return lhs.status.sortOrder < rhs.status.sortOrder
        }
        if lhs.sortIndex != rhs.sortIndex {
            return lhs.sortIndex < rhs.sortIndex
        }
        return lhs.createdAt < rhs.createdAt
    }
}

