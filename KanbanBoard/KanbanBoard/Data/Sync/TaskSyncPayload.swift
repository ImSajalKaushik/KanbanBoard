//
//  TaskSyncPayload.swift
//  KanbanBoard
//
//  Created by Sajal Kaushik on 04/09/26.
//

import FirebaseFirestore
import Foundation

struct TaskSyncPayload: Codable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case details
        case status
        case sortIndex
        case createdAt
        case updatedAt
        case isDeleted
    }

    let id: String
    var title: String
    var details: String
    var status: TaskStatus
    var sortIndex: Int64
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool

    init(id: String,
         title: String,
         details: String,
         status: TaskStatus,
         sortIndex: Int64,
         createdAt: Date,
         updatedAt: Date,
         isDeleted: Bool) {
        self.id = id
        self.title = title
        self.details = details
        self.status = status
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }

    init?(document: DocumentSnapshot) {
        let data = document.data() ?? [:]
          guard let title = data[CodingKeys.title.rawValue] as? String,
              let details = data[CodingKeys.details.rawValue] as? String,
              let statusValue = data[CodingKeys.status.rawValue] as? String,
              let status = TaskStatus(rawValue: statusValue),
              let sortIndex = (data[CodingKeys.sortIndex.rawValue] as? NSNumber)?.int64Value,
              let createdAt = data[CodingKeys.createdAt.rawValue] as? Timestamp,
              let updatedAt = data[CodingKeys.updatedAt.rawValue] as? Timestamp else {
            return nil
        }

        self.init(
            id: document.documentID,
            title: title,
            details: details,
            status: status,
            sortIndex: sortIndex,
            createdAt: createdAt.dateValue(),
            updatedAt: updatedAt.dateValue(),
            isDeleted: data[CodingKeys.isDeleted.rawValue] as? Bool ?? false
        )
    }
}
