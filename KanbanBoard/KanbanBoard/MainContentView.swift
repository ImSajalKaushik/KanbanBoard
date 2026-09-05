//
//  MainContentView.swift
//  KanbanBoard
//
//  Created by Sajal Kaushik on 04/09/26.
//

import SwiftUI

struct MainContentView: View {
    @ObservedObject private var viewModel: KanbanViewModel
    @State private var isPresentingNewTask = false

    init(viewModel: KanbanViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Kanban Board")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if case .loaded = viewModel.state {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                isPresentingNewTask = true
                            } label: {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel("Add Task")
                        }
                    }
                }
        }
        .sheet(isPresented: $isPresentingNewTask) {
            NavigationStack {
                TaskEditorView(viewModel: viewModel)
            }
        }
        .task {
            guard case .loading = viewModel.state else { return }
            await viewModel.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("Loading tasks")
        case .loaded:
            KanbanBoardView(viewModel: viewModel)
        case .failed(let message):
            ContentUnavailableView {
                Label("Tasks Unavailable", systemImage: "externaldrive.badge.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") {
                    Task { await viewModel.load() }
                }
            }
        }
    }
}

#Preview {
    MainContentView(
        viewModel: KanbanViewModel(
            tasks: [
                BoardTask(title: "Plan board", details: "Define the first interaction pass."),
                BoardTask(title: "Add persistence", status: .done, syncState: .synced)
            ]
        )
    )
}
