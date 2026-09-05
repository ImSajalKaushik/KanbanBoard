//
//  TaskCardView.swift
//  KanbanBoard
//
//  Created by Sajal Kaushik on 04/09/26.
//

import SwiftUI

struct TaskCardView: View {
    let task: BoardTask

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(task.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !task.details.isEmpty {
                Text(task.details)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            syncStatus
        }
        .padding(14)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(uiColor: .separator).opacity(0.35), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Opens task details. Touch and hold to move this task.")
    }

    @ViewBuilder
    private var syncStatus: some View {
        switch task.syncState {
        case .pending:
            Label("Pending sync", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed:
            Label("Sync failed", systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                .font(.caption)
                .foregroundStyle(.red)
        case .synced:
            EmptyView()
        }
    }

    private var accessibilityDescription: String {
        var parts = [task.title, task.status.title]
        if !task.details.isEmpty {
            parts.append(task.details)
        }
        if task.syncState == .pending {
            parts.append("Pending sync")
        } else if task.syncState == .failed {
            parts.append("Sync failed")
        }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    TaskCardView(
        task: BoardTask(
            title: "Review board interaction",
            details: "Check drag targets and compact-width navigation.",
            status: .inProgress
        )
    )
    .padding()
    .background(Color(uiColor: .secondarySystemBackground))
}