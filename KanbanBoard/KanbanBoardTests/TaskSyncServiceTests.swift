//
//  TaskSyncServiceTests.swift
//  KanbanBoardTests
//
//  Created by Sajal Kaushik on 04/09/26.
//

import Combine
import XCTest
@testable import KanbanBoard

@MainActor
final class TaskSyncServiceTests: XCTestCase {
    func testListenerFailureMarksPendingTasksFailedAndNotifies() async {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let task = TaskSyncPayload(
            id: UUID().uuidString,
            title: "Pending task",
            details: "",
            status: .todo,
            sortIndex: 0,
            createdAt: timestamp,
            updatedAt: timestamp,
            isDeleted: false
        )
        let localStore = SyncStoreStub(pendingTasks: [task])
        let remoteAPI = TaskAPIStub()
        let networkMonitor = NetworkMonitorStub()
        let service = TaskSyncService(
            localStore: localStore,
            remoteAPI: remoteAPI,
            networkMonitor: networkMonitor
        )
        let didChange = expectation(description: "Tasks changed")
        service.onTasksChanged = {
            didChange.fulfill()
        }

        service.start()
        await Task.yield()
        remoteAPI.finish(throwing: RemoteTaskObservationError.failure("Missing or insufficient permissions."))

        await fulfillment(of: [didChange], timeout: 1)
        XCTAssertEqual(localStore.failedTaskID, task.id)
        XCTAssertEqual(localStore.failureMessage, "Missing or insufficient permissions.")
        service.stop()
    }
}

@MainActor
private final class SyncStoreStub: LocalTaskSyncStore {
    private let pendingTasks: [TaskSyncPayload]
    private(set) var failedTaskID: String?
    private(set) var failureMessage: String?

    init(pendingTasks: [TaskSyncPayload]) {
        self.pendingTasks = pendingTasks
    }

    func fetchPendingSyncTasks() async throws -> [TaskSyncPayload] {
        pendingTasks
    }

    func reconcileRemoteTasks(_ tasks: [TaskSyncPayload],
                              removeMissingSyncedTasks: Bool) async throws -> Bool {
        false
    }

    func markTaskSynced(id: String, expectedUpdatedAt: Date) async throws -> Bool {
        false
    }

    func markTaskFailed(id: String,
                        expectedUpdatedAt: Date,
                        message: String) async throws -> Bool {
        failedTaskID = id
        failureMessage = message
        return true
    }
}

@MainActor
private final class TaskAPIStub: TaskAPI {
    private var continuation: AsyncThrowingStream<RemoteTaskSnapshot, Error>.Continuation?

    func fetchTasks() async throws -> [TaskSyncPayload] {
        []
    }

    func fetchTask(id: String) async throws -> TaskSyncPayload? {
        nil
    }

    func upsertTask(_ task: TaskSyncPayload) async throws {}

    func observeTasks() -> AsyncThrowingStream<RemoteTaskSnapshot, Error> {
        AsyncThrowingStream<RemoteTaskSnapshot, Error> { continuation in
            self.continuation = continuation
        }
    }

    func finish(throwing error: Error) {
        continuation?.finish(throwing: error)
    }
}

private final class NetworkMonitorStub: NetworkMonitoring {
    let isConnected = false

    var connectivityPublisher: AnyPublisher<Bool, Never> {
        Just(isConnected).eraseToAnyPublisher()
    }
}
