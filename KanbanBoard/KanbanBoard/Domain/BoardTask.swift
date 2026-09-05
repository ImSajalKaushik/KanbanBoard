//
//  BoardTask.swift
//  KanbanBoard
//
//  Created by Sajal Kaushik on 04/09/26.
//

import Foundation

enum TaskStatus: String, CaseIterable, Codable, Sendable {
    case todo
    case inProgress
    case done

    var title: String {
        switch self {
        case .todo:
            "To Do"
        case .inProgress:
            "In Progress"
        case .done:
            "Done"
        }
    }

    var sortOrder: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}

enum TaskSyncState: String, Codable, Sendable {
    case pending
    case synced
    case failed
}

struct BoardTask: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var title: String
    var details: String
    var status: TaskStatus
    var sortIndex: Int64
    let createdAt: Date
    var updatedAt: Date
    var syncState: TaskSyncState
    var lastSyncError: String?

    init(id: String = UUID().uuidString,
         title: String,
         details: String = "",
         status: TaskStatus = .todo,
         sortIndex: Int64 = 0,
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         syncState: TaskSyncState = .pending,
         lastSyncError: String? = nil
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.status = status
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncState = syncState
        self.lastSyncError = lastSyncError
    }
}

extension BoardTask {
    /// Placeholder for a task the user is composing. Identity, ordering, and sync
    /// metadata here are provisional; the repository assigns the stored values.
    static func draft(status: TaskStatus = .todo) -> BoardTask {
        BoardTask(title: "", status: status)
    }

    var hasValidTitle: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}