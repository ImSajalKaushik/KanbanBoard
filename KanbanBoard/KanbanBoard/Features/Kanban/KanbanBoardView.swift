//
//  KanbanBoardView.swift
//  KanbanBoard
//
//  Created by Sajal Kaushik on 04/09/26.
//

import SwiftUI

enum BoardLayout {
    static let boardPadding: CGFloat = 8
    static let columnSpacing: CGFloat = 6
    static let cornerRadius: CGFloat = 8
    static let columnContentPadding: CGFloat = 6
    static let cardSpacing: CGFloat = 12

    static let headerHeight: CGFloat = 64
    static let headerPadding: CGFloat = 8
    static let headerSpacing: CGFloat = 6
    static let statusDotSize: CGFloat = 8
    static let statusDotTopPadding: CGFloat = 4
    static let countBadgeHorizontalPadding: CGFloat = 6
    static let countBadgeVerticalPadding: CGFloat = 2

    static let emptyStateSpacing: CGFloat = 8
    static let emptyStateMinHeight: CGFloat = 180

    static let dropHighlightOpacity: CGFloat = 0.1
    static let dropHighlightLineWidth: CGFloat = 2
    static let dropHighlightAnimationDuration: TimeInterval = 0.15
    static let movingCardOpacity: CGFloat = 0.55

    /// Columns visible at once before the board scrolls horizontally.
    static let compactColumnLimit = 3
    static let regularColumnLimit = 4
}

struct KanbanBoardView: View {
    @ObservedObject private var viewModel: KanbanViewModel

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var targetedStatus: TaskStatus?
    @State private var taskBeingMoved: String?
    @State private var moveErrorMessage: String?

    init(viewModel: KanbanViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: BoardLayout.columnSpacing) {
                ForEach(orderedStatuses, id: \.self) { status in
                    StatusColumnView(
                        status: status,
                        tasks: tasks(in: status),
                        movingTaskID: taskBeingMoved,
                        isTargeted: targetedStatus == status,
                        onSelect: { viewModel.selectedTask = $0 },
                        onDrop: { handleDrop($0, into: status) },
                        onTargetChange: { updateTarget(status, isTargeted: $0) }
                    )
                    .containerRelativeFrame(
                        .horizontal,
                        count: visibleColumnCount,
                        spacing: BoardLayout.columnSpacing
                    )
                }
            }
            .scrollTargetLayout()
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .safeAreaPadding(.horizontal, BoardLayout.boardPadding)
        .safeAreaPadding(.bottom, BoardLayout.boardPadding)
        .background(Color(uiColor: .systemGroupedBackground))
        .alert("Couldn't Move Task", isPresented: isShowingMoveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(moveErrorMessage ?? "")
        }
        .navigationDestination(item: $viewModel.selectedTask) { task in
            TaskEditorView(viewModel: viewModel, task: task)
        }
    }

    private var orderedStatuses: [TaskStatus] {
        TaskStatus.allCases.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// iPhone portrait shows three columns; wider layouts show four before scrolling.
    private var visibleColumnCount: Int {
        let limit = horizontalSizeClass == .compact && verticalSizeClass == .regular
            ? BoardLayout.compactColumnLimit
            : BoardLayout.regularColumnLimit
        return min(orderedStatuses.count, limit)
    }

    private var isShowingMoveError: Binding<Bool> {
        Binding(
            get: { moveErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    moveErrorMessage = nil
                }
            }
        )
    }

    private func tasks(in status: TaskStatus) -> [BoardTask] {
        viewModel.tasks
            .filter { $0.status == status }
            .sorted {
                if $0.sortIndex == $1.sortIndex {
                    return $0.createdAt < $1.createdAt
                }
                return $0.sortIndex < $1.sortIndex
            }
    }

    private func updateTarget(_ status: TaskStatus, isTargeted: Bool) {
        if isTargeted {
            targetedStatus = status
        } else if targetedStatus == status {
            targetedStatus = nil
        }
    }

    private func handleDrop(_ payloads: [String], into status: TaskStatus) -> Bool {
        guard taskBeingMoved == nil,
              let taskID = payloads.first,
              let task = viewModel.tasks.first(where: { $0.id == taskID }),
              task.status != status else {
            return false
        }

        taskBeingMoved = taskID
        Task {
            defer { taskBeingMoved = nil }
            do {
                try await viewModel.moveTask(id: taskID, to: status)
            } catch {
                moveErrorMessage = error.localizedDescription
            }
        }
        return true
    }
}

#Preview {
    let tasks = [
        BoardTask(title: "Define board layout", details: "Keep all states visible.", status: .todo),
        BoardTask(title: "Define board layout", details: "Keep all states visible.", status: .todo),
        BoardTask(title: "Define board layout", details: "Keep all states visible.", status: .todo),
        BoardTask(title: "Define board layout", details: "Keep all states visible.", status: .todo),
        BoardTask(title: "Build drag target", status: .inProgress),
        BoardTask(title: "Persist tasks", status: .done, syncState: .synced)
    ]

    NavigationStack {
        KanbanBoardView(viewModel: KanbanViewModel(tasks: tasks))
            .navigationTitle("Kanban Board")
    }
}
