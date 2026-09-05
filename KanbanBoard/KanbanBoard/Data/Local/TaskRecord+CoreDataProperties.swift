//
//  TaskRecord+CoreDataProperties.swift
//  KanbanBoard
//
//  Created by Sajal Kaushik on 04/09/26.
//

import CoreData

extension TaskRecord {
    @nonobjc nonisolated class func fetchRequest() -> NSFetchRequest<TaskRecord> {
        NSFetchRequest<TaskRecord>(entityName: "TaskRecord")
    }

    // we can have user id relationship later which will enable us to fetch user id related todo and for cleanup
    @NSManaged nonisolated var id: String
    @NSManaged nonisolated var title: String
    @NSManaged nonisolated var statusRaw: String
    @NSManaged nonisolated var details: String
    
    @NSManaged nonisolated var createdAt: Date
    @NSManaged nonisolated var updatedAt: Date
    
    @NSManaged nonisolated var syncStateRaw: String
    @NSManaged nonisolated var lastSyncError: String?
    
    @NSManaged nonisolated var isTombstone: Bool
    @NSManaged nonisolated var sortIndex: Int64

}
