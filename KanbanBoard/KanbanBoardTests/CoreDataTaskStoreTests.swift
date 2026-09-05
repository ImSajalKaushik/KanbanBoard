//
//  CoreDataTaskStoreTests.swift
//  KanbanBoardTests
//
//  Created by Sajal Kaushik on 04/09/26.
//

import CoreData
import XCTest
@testable import KanbanBoard

@MainActor
final class CoreDataTaskStoreTests: XCTestCase {
    func testCreateTrimsInputAndUsesPerStatusOrdering() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let (_, repository) = try await makeInMemoryRepository(now: now)

        let first = try await repository.createTask(
            title: "  First task  ",
            details: "  First details  "
        )
        let second = try await repository.createTask(title: "Second task", details: "")
        let done = try await repository.createTask(
            title: "Done task",
            details: "",
            status: .done
        )

        XCTAssertEqual(first.title, "First task")
        XCTAssertEqual(first.details, "First details")
        XCTAssertEqual(first.sortIndex, 0)
        XCTAssertEqual(second.sortIndex, 1)
        XCTAssertEqual(done.sortIndex, 0)
        XCTAssertEqual(first.syncState, .pending)

        let tasks = try await repository.fetchTasks()
        XCTAssertEqual(tasks.map(\.id), [first.id, second.id, done.id])
    }

    func testEmptyTitleIsRejectedWithoutPersistingTask() async throws {
        let (_, repository) = try await makeInMemoryRepository()

        do {
            _ = try await repository.createTask(title: " \n ", details: "Ignored")
            XCTFail("Expected an empty-title validation error")
        } catch {
            XCTAssertEqual(error as? TaskRepositoryError, .emptyTitle)
        }

        let tasks = try await repository.fetchTasks()
        XCTAssertTrue(tasks.isEmpty)
    }

    func testReorderMoveUpdateAndDeleteRemainConsistent() async throws {
        let (controller, repository) = try await makeInMemoryRepository()
        let first = try await repository.createTask(title: "First", details: "")
        let second = try await repository.createTask(title: "Second", details: "")
        let third = try await repository.createTask(title: "Third", details: "")

        _ = try await repository.moveTask(id: first.id, to: .done, destinationIndex: 0)
        let updated = try await repository.updateTask(
            id: first.id,
            title: "Updated",
            details: "Description",
            status: .inProgress
        )
        try await repository.deleteTask(id: third.id)

        XCTAssertEqual(updated.status, .inProgress)
        XCTAssertEqual(updated.title, "Updated")

        let remaining = try await repository.fetchTasks()
        XCTAssertEqual(remaining.map(\.id), [second.id, first.id])
        XCTAssertEqual(remaining.map(\.sortIndex), [0, 0])

        let request = TaskRecord.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", third.id)
        let tombstone = try XCTUnwrap(controller.container.viewContext.fetch(request).first)
        XCTAssertTrue(tombstone.isTombstone)
        XCTAssertEqual(tombstone.syncStateRaw, TaskSyncState.pending.rawValue)
    }

    func testMoveWithoutDestinationIndexAppendsAndCompactsStatuses() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let firstTodo = try await repository.createTask(title: "First To Do", details: "")
        let secondTodo = try await repository.createTask(title: "Second To Do", details: "")
        let firstDone = try await repository.createTask(
            title: "First Done",
            details: "",
            status: .done
        )
        let secondDone = try await repository.createTask(
            title: "Second Done",
            details: "",
            status: .done
        )

        let moved = try await repository.moveTask(id: firstTodo.id, to: .done)

        XCTAssertEqual(moved.status, .done)
        XCTAssertEqual(moved.sortIndex, 2)
        XCTAssertEqual(moved.syncState, .pending)

        let tasks = try await repository.fetchTasks()
        let todoTasks = tasks.filter { $0.status == .todo }
        let doneTasks = tasks.filter { $0.status == .done }

        XCTAssertEqual(todoTasks.map(\.id), [secondTodo.id])
        XCTAssertEqual(todoTasks.map(\.sortIndex), [0])
        XCTAssertEqual(doneTasks.map(\.id), [firstDone.id, secondDone.id, firstTodo.id])
        XCTAssertEqual(doneTasks.map(\.sortIndex), [0, 1, 2])
    }

    func testTasksPersistAfterSQLiteContainerIsRecreated() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("KanbanBoard.sqlite")
        var firstController: PersistenceController? = try PersistenceController(storeURL: storeURL)
        try await firstController?.load()
        let firstStore = CoreDataTaskStore(context: try XCTUnwrap(firstController).newBackgroundContext())
        let firstRepository = TaskRepository(localStore: firstStore)
        let created = try await firstRepository.createTask(title: "Persistent", details: "Task")

        if let coordinator = firstController?.container.persistentStoreCoordinator {
            for store in coordinator.persistentStores {
                try coordinator.remove(store)
            }
        }
        firstController = nil

        let secondController = try PersistenceController(storeURL: storeURL)
        try await secondController.load()
        let secondStore = CoreDataTaskStore(context: secondController.newBackgroundContext())
        let secondRepository = TaskRepository(localStore: secondStore)

        let tasks = try await secondRepository.fetchTasks()
        XCTAssertEqual(tasks.map(\.id), [created.id])
        XCTAssertEqual(tasks.first?.title, "Persistent")
    }

    func testReconcileKeepsSyncedTaskStableAcrossTimestampPrecisionDrift() async throws {
        let timestamp = Date(timeIntervalSince1970: 1_000.123_456_789)
        let controller = try PersistenceController(inMemory: true)
        try await controller.load()
        let store = CoreDataTaskStore(context: controller.newBackgroundContext())
        let repository = TaskRepository(localStore: store, now: { timestamp })
        let task = try await repository.createTask(title: "Stable sync", details: "")
        let didMarkSynced = try await store.markTaskSynced(
            id: task.id,
            expectedUpdatedAt: timestamp
        )
        XCTAssertTrue(didMarkSynced)

        let remoteTask = TaskSyncPayload(
            id: task.id,
            title: task.title,
            details: task.details,
            status: task.status,
            sortIndex: task.sortIndex,
            createdAt: task.createdAt,
            updatedAt: timestamp.addingTimeInterval(-0.000_000_1),
            isDeleted: false
        )

        let didChange = try await store.reconcileRemoteTasks(
            [remoteTask],
            removeMissingSyncedTasks: true
        )

        XCTAssertFalse(didChange)
        let syncedTask = try await repository.fetchTasks().first
        XCTAssertEqual(syncedTask?.syncState, .synced)
    }

    func testReconcileAppliesRemoteEditThatKeepsTheSameUpdatedAt() async throws {
        let timestamp = Date(timeIntervalSince1970: 1_000.123_456_789)
        let controller = try PersistenceController(inMemory: true)
        try await controller.load()
        let store = CoreDataTaskStore(context: controller.newBackgroundContext())
        let repository = TaskRepository(localStore: store, now: { timestamp })
        let task = try await repository.createTask(title: "Console edit", details: "")
        _ = try await store.markTaskSynced(id: task.id, expectedUpdatedAt: timestamp)

        // A Firestore console edit changes fields without touching updatedAt, and the
        // timestamp round trip can come back marginally older than the local copy.
        let remoteTask = TaskSyncPayload(
            id: task.id,
            title: "Edited in console",
            details: task.details,
            status: task.status,
            sortIndex: task.sortIndex,
            createdAt: task.createdAt,
            updatedAt: timestamp.addingTimeInterval(-0.000_000_1),
            isDeleted: false
        )

        let didChange = try await store.reconcileRemoteTasks(
            [remoteTask],
            removeMissingSyncedTasks: true
        )

        XCTAssertTrue(didChange)
        let reconciledTask = try await repository.fetchTasks().first
        XCTAssertEqual(reconciledTask?.title, "Edited in console")
        XCTAssertEqual(reconciledTask?.syncState, .synced)
    }

    private func makeInMemoryRepository(
        now: Date = Date(timeIntervalSince1970: 1_000)
    ) async throws -> (PersistenceController, TaskRepository) {
        let controller = try PersistenceController(inMemory: true)
        try await controller.load()
        let store = CoreDataTaskStore(context: controller.newBackgroundContext())
        let repository = TaskRepository(localStore: store, now: { now })
        return (controller, repository)
    }
}