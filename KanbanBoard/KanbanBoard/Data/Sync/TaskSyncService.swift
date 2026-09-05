//
//  TaskSyncService.swift
//  KanbanBoard
//
//  Created by Sajal Kaushik on 04/09/26.
//

import Combine
import Foundation

@MainActor
protocol TaskSyncTriggering: AnyObject {
    func requestSync()
}

@MainActor
protocol TaskSyncControlling: TaskSyncTriggering {
    var onTasksChanged: (@MainActor () -> Void)? { get set }

    func start()
    func stop()
}

@MainActor
final class TaskSyncService: TaskSyncControlling {
    var onTasksChanged: (@MainActor () -> Void)?

    private let localStore: any LocalTaskSyncStore
    private let remoteAPI: any TaskAPI
    private let networkMonitor: any NetworkMonitoring

    private var networkCancellable: AnyCancellable?
    private var remoteObservationTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var pendingRemoteSnapshot: RemoteTaskSnapshot?
    private var hasReconciledServerSnapshot = false
    private var needsSync = false
    private var isStarted = false

    init(localStore: any LocalTaskSyncStore,
         remoteAPI: any TaskAPI,
         networkMonitor: any NetworkMonitoring
    ) {
        self.localStore = localStore
        self.remoteAPI = remoteAPI
        self.networkMonitor = networkMonitor
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        startRemoteObservationIfNeeded()
        networkCancellable = networkMonitor.connectivityPublisher.sink { [weak self] isConnected in
            guard isConnected else { return }
            Task { @MainActor [weak self] in
                self?.requestSync()
            }
        }
        requestSync()
    }

    func stop() {
        isStarted = false
        networkCancellable = nil
        remoteObservationTask?.cancel()
        remoteObservationTask = nil
        syncTask?.cancel()
        syncTask = nil
        pendingRemoteSnapshot = nil
        hasReconciledServerSnapshot = false
        needsSync = false
    }

    func requestSync() {
        needsSync = true
        guard isStarted else { return }

        startRemoteObservationIfNeeded()
        guard syncTask == nil else { return }
        syncTask = Task { [weak self] in
            await self?.drainSyncRequests()
        }
    }

    private func startRemoteObservationIfNeeded() {
        guard remoteObservationTask == nil else { return }
        remoteObservationTask = Task { [weak self] in
            guard let self else { return }

            do {
                for try await snapshot in self.remoteAPI.observeTasks() {
                    guard !Task.isCancelled else { return }
                    self.handleRemoteSnapshot(snapshot)
                }
            } catch is CancellationError {
                return
            } catch {
                self.handleRemoteObservationFailure(error.localizedDescription)
            }
        }
    }

    private func handleRemoteSnapshot(_ snapshot: RemoteTaskSnapshot) {
        guard isStarted else { return }
        guard snapshot.isServerConfirmed else { return }
        pendingRemoteSnapshot = snapshot
        requestSync()
    }

    private func handleRemoteObservationFailure(_ message: String) {
        guard isStarted else { return }
        remoteObservationTask = nil
        hasReconciledServerSnapshot = false
        Task { [weak self] in
            await self?.markPendingTasksFailed(message: message)
        }
    }

    private func markPendingTasksFailed(message: String) async {
        do {
            let pendingTasks = try await localStore.fetchPendingSyncTasks()
            var didChange = false
            for task in pendingTasks {
                if try await localStore.markTaskFailed(
                    id: task.id,
                    expectedUpdatedAt: task.updatedAt,
                    message: message
                ) {
                    didChange = true
                }
            }
            if didChange {
                onTasksChanged?()
            }
        } catch {
            return
        }
    }

    private func drainSyncRequests() async {
        while needsSync, !Task.isCancelled, isStarted {
            needsSync = false
            await reconcilePendingRemoteSnapshot()
            await syncPendingLocalTasksIfReady()
        }

        syncTask = nil
        if needsSync, isStarted {
            requestSync()
        }
    }

    private func reconcilePendingRemoteSnapshot() async {
        guard let snapshot = pendingRemoteSnapshot else { return }
        pendingRemoteSnapshot = nil

        do {
            let didChange = try await localStore.reconcileRemoteTasks(
                snapshot.tasks,
                removeMissingSyncedTasks: true
            )
            hasReconciledServerSnapshot = true
            if didChange {
                onTasksChanged?()
            }
        } catch {
            if pendingRemoteSnapshot == nil {
                pendingRemoteSnapshot = snapshot
            }
        }
    }

    private func syncPendingLocalTasksIfReady() async {
        guard hasReconciledServerSnapshot, networkMonitor.isConnected else { return }

        let pendingTasks: [TaskSyncPayload]
        do {
            pendingTasks = try await localStore.fetchPendingSyncTasks()
        } catch {
            return
        }

        for task in pendingTasks {
            guard !Task.isCancelled, isStarted, networkMonitor.isConnected else { return }
            await syncPendingTask(task)
        }
    }

    private func syncPendingTask(_ task: TaskSyncPayload) async {
        do {
            try await remoteAPI.upsertTask(task)
            guard !Task.isCancelled, isStarted else { return }

            if try await localStore.markTaskSynced(
                id: task.id,
                expectedUpdatedAt: task.updatedAt
            ) {
                onTasksChanged?()
            }
        } catch {
            do {
                if try await localStore.markTaskFailed(
                    id: task.id,
                    expectedUpdatedAt: task.updatedAt,
                    message: error.localizedDescription
                ) {
                    onTasksChanged?()
                }
            } catch {
                return
            }
        }
    }
}