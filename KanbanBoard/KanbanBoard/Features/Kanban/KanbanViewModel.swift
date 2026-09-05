//
//  KanbanViewModel.swift
//  KanbanBoard
//
//  Created by Sajal Kaushik on 04/09/26.
//

import Combine
import Foundation

enum KanbanViewModelError: LocalizedError {
    case repositoryUnavailable

    var errorDescription: String? {
        switch self {
        case .repositoryUnavailable:
            "Tasks are not ready yet."
        }
    }
}

extension KanbanViewModel {
    /// Single production assembly point for the view model's repository dependency.
    static func makeDefault() throws -> KanbanViewModel {
        try KanbanViewModel(repository: TaskRepository.makeDefault())
    }
}

@MainActor
final class KanbanViewModel: ObservableObject {
    enum State {
        case loading
        case loaded([BoardTask])
        case failed(String)
    }

    @Published private(set) var state: State
    @Published var selectedTask: BoardTask?

    var tasks: [BoardTask] {
        guard case .loaded(let tasks) = state else { return [] }
        return tasks
    }

    private let repository: TaskRepository?

    init(repository: TaskRepository) {
        self.repository = repository
        state = .loading
        repository.onTasksChanged = { [weak self] in
            Task { [weak self] in
                await self?.refreshTasks()
            }
        }
    }

    init(errorMessage: String) {
        repository = nil
        state = .failed(errorMessage)
    }

    init(tasks: [BoardTask]) {
        repository = nil
        state = .loaded(tasks)
    }

    func load() async {
        guard let repository else { return }
        state = .loading

        do {
            try await repository.load()
            let tasks = try await repository.fetchTasks()
            state = .loaded(tasks)
            repository.startSync()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func requestSync() {
        repository?.startSync()
    }

    func stopSync() {
        repository?.stopSync()
    }

    /// Only the user-editable fields are read; the repository owns ordering and sync metadata.
    func createTask(_ task: BoardTask) async throws {
        guard let repository else {
            throw KanbanViewModelError.repositoryUnavailable
        }
        _ = try await repository.createTask(
            title: task.title,
            details: task.details,
            status: task.status
        )
        try await reloadTasks(from: repository)
    }

    func updateTask(_ task: BoardTask) async throws {
        guard let repository else {
            throw KanbanViewModelError.repositoryUnavailable
        }
        _ = try await repository.updateTask(
            id: task.id,
            title: task.title,
            details: task.details,
            status: task.status
        )
        try await reloadTasks(from: repository)
    }

    func deleteTask(id: String) async throws {
        guard let repository else {
            throw KanbanViewModelError.repositoryUnavailable
        }
        try await repository.deleteTask(id: id)
        try await reloadTasks(from: repository)
    }

    func moveTask(id: String, to status: TaskStatus) async throws {
        guard let repository else {
            throw KanbanViewModelError.repositoryUnavailable
        }
        _ = try await repository.moveTask(id: id, to: status)
        try await reloadTasks(from: repository)
    }

    private func refreshTasks() async {
        guard let repository else { return }
        do {
            state = .loaded(try await repository.fetchTasks())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func reloadTasks(from repository: TaskRepository) async throws {
        // given the ux, pagination is intentionally avoaided for now
        // we can expand fetch based on intial filters [user id based, months based etc]
        state = .loaded(try await repository.fetchTasks())
    }
}
