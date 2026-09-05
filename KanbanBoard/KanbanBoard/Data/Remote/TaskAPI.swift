//
//  TaskAPI.swift
//  KanbanBoard
//
//  Created by Sajal Kaushik on 04/09/26.
//

import Foundation

struct RemoteTaskSnapshot: Sendable {
    let tasks: [TaskSyncPayload]
    let isFromCache: Bool
    let hasPendingWrites: Bool

    var isServerConfirmed: Bool {
        !isFromCache && !hasPendingWrites
    }
}

enum RemoteTaskObservationError: LocalizedError, Sendable, Equatable {
    case listenerEndedWithoutResult
    case failure(String)

    var errorDescription: String? {
        switch self {
        case .listenerEndedWithoutResult:
            "The remote task listener ended without a snapshot or error."
        case .failure(let message):
            message
        }
    }
}

@MainActor
protocol TaskAPI {
    func fetchTasks() async throws -> [TaskSyncPayload]
    func fetchTask(id: String) async throws -> TaskSyncPayload?
    func upsertTask(_ task: TaskSyncPayload) async throws
    func observeTasks() -> AsyncThrowingStream<RemoteTaskSnapshot, Error>
}
