//
//  LocalTaskStore.swift
//  KanbanBoard
//
//  Created by Sajal Kaushik on 04/09/26.
//

import Foundation

@MainActor
protocol LocalTaskStore {
    func fetchTasks() async throws -> [BoardTask]

    func createTask(title: String,
                    details: String,
                    status: TaskStatus,
                    createdAt: Date) async throws -> BoardTask

    func updateTask(id: String,
                    title: String,
                    details: String,
                    status: TaskStatus,
                    updatedAt: Date) async throws -> BoardTask
    
    func deleteTask(id: String, deletedAt: Date) async throws
    
    func moveTask(id: String,
                  to status: TaskStatus,
                  destinationIndex: Int?,
                  updatedAt: Date) async throws -> BoardTask
}

@MainActor
protocol LocalTaskSyncStore: AnyObject {
    func fetchPendingSyncTasks() async throws -> [TaskSyncPayload]
    
    func reconcileRemoteTasks(_ tasks: [TaskSyncPayload],
                              removeMissingSyncedTasks: Bool) async throws -> Bool
    
    func markTaskSynced(id: String,
                        expectedUpdatedAt: Date) async throws -> Bool
    
    func markTaskFailed(id: String,
                        expectedUpdatedAt: Date,
                        message: String) async throws -> Bool
}
