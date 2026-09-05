//
//  StatusColumnView.swift
//  KanbanBoard
//
//  Created by Sajal Kaushik on 05/09/26.
//

import SwiftUI

struct StatusColumnView: View {
    let status: TaskStatus
    let tasks: [BoardTask]
    let movingTaskID: String?
    let isTargeted: Bool
    let onSelect: (BoardTask) -> Void
    let onDrop: ([String]) -> Bool
    let onTargetChange: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            taskList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            isTargeted
                ? statusColor.opacity(BoardLayout.dropHighlightOpacity)
                : Color(uiColor: .secondarySystemGroupedBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: BoardLayout.cornerRadius)
                .stroke(isTargeted ? statusColor : .clear, lineWidth: BoardLayout.dropHighlightLineWidth)
        }
        .clipShape(RoundedRectangle(cornerRadius: BoardLayout.cornerRadius))
        .dropDestination(for: String.self) { payloads, _ in
            onDrop(payloads)
        } isTargeted: { isTargeted in
            onTargetChange(isTargeted)
        }
        .animation(.easeInOut(duration: BoardLayout.dropHighlightAnimationDuration), value: isTargeted)
    }

    private var statusColor: Color {
        switch status {
        case .todo:
            .blue
        case .inProgress:
            .orange
        case .done:
            .green
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: BoardLayout.headerSpacing) {
            Circle()
                .fill(statusColor)
                .frame(width: BoardLayout.statusDotSize, height: BoardLayout.statusDotSize)
                .padding(.top, BoardLayout.statusDotTopPadding)
                .accessibilityHidden(true)

            Text(status.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(tasks.count, format: .number)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, BoardLayout.countBadgeHorizontalPadding)
                .padding(.vertical, BoardLayout.countBadgeVerticalPadding)
                .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                .accessibilityLabel("\(tasks.count) tasks")
        }
        .padding(BoardLayout.headerPadding)
        .frame(height: BoardLayout.headerHeight, alignment: .top)
    }

    private var taskList: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: BoardLayout.cardSpacing) {
                if tasks.isEmpty {
                    emptyState
                } else {
                    ForEach(tasks) { task in
                        card(for: task)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(BoardLayout.columnContentPadding)
        }
    }

    private var emptyState: some View {
        VStack(spacing: BoardLayout.emptyStateSpacing) {
            Image(systemName: "tray")
                .font(.title3)
            Text("No tasks")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: BoardLayout.emptyStateMinHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No tasks in \(status.title)")
    }

    private func card(for task: BoardTask) -> some View {
        TaskCardView(task: task)
            .contentShape(.dragPreview, RoundedRectangle(cornerRadius: BoardLayout.cornerRadius))
            .contentShape(.interaction, Rectangle())
            .onTapGesture {
                onSelect(task)
            }
            .opacity(movingTaskID == task.id ? BoardLayout.movingCardOpacity : 1)
            .draggable(task.id)
    }
}

#Preview {
    StatusColumnView(
        status: .todo,
        tasks: [
            BoardTask(title: "Define board layout", details: "Keep all states visible."),
            BoardTask(title: "Persist tasks", syncState: .synced)
        ],
        movingTaskID: nil,
        isTargeted: false,
        onSelect: { _ in },
        onDrop: { _ in false },
        onTargetChange: { _ in }
    )
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}
