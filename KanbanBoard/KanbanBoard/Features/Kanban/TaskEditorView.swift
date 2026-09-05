//
//  TaskEditorView.swift
//  KanbanBoard
//
//  Created by Sajal Kaushik on 04/09/26.
//

import SwiftUI

struct TaskEditorView: View {
    @ObservedObject private var viewModel: KanbanViewModel
    @Environment(\.dismiss) private var dismiss

    private let task: BoardTask?

    @State private var draft: BoardTask
    @State private var isSaving = false
    @State private var isConfirmingDeletion = false
    @State private var errorTitle = ""
    @State private var errorMessage: String?

    init(viewModel: KanbanViewModel, task: BoardTask? = nil) {
        self.viewModel = viewModel
        let task = task ?? viewModel.selectedTask
        self.task = task
        _draft = State(initialValue: task ?? .draft())
    }

    var body: some View {
        Form {
            Section("Task") {
                TextField("Title", text: $draft.title)
                    .textInputAutocapitalization(.sentences)

                TextEditor(text: $draft.details)
                    .frame(minHeight: 140)
                    .accessibilityLabel("Details")
            }

            Section("State") {
                Picker("State", selection: $draft.status) {
                    ForEach(TaskStatus.allCases, id: \.self) { status in
                        Text(status.title).tag(status)
                    }
                }
            }

            if let task {
                Section("Sync") {
                    Label(syncTitle(for: task), systemImage: syncIcon(for: task))
                        .foregroundStyle(syncColor(for: task))

                    if let lastSyncError = task.lastSyncError, !lastSyncError.isEmpty {
                        Text(lastSyncError)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        isConfirmingDeletion = true
                    } label: {
                        if isSaving {
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Label("Delete Task", systemImage: "trash")
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .navigationTitle(task == nil ? "New Task" : "Task Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if task == nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismissEditor()
                    }
                    .disabled(isSaving)
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(action: save) {
                    ZStack {
                        Text("Save")
                            .opacity(isSaving ? 0 : 1)
                        if isSaving {
                            ProgressView()
                        }
                    }
                }
                .disabled(isSaveDisabled)
            }
        }
        .confirmationDialog(
            "Delete this task?",
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete Task", role: .destructive, action: deleteTask)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This change will be saved locally and synced when a connection is available.")
        }
        .alert(errorTitle, isPresented: isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var isSaveDisabled: Bool {
        isSaving || !draft.hasValidTitle
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }

    private func save() {
        guard !isSaveDisabled else { return }
        isSaving = true

        Task {
            do {
                if task == nil {
                    try await viewModel.createTask(draft)
                } else {
                    try await viewModel.updateTask(draft)
                }
                dismissEditor()
            } catch {
                errorTitle = "Couldn't Save Task"
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }

    private func deleteTask() {
        guard let task, !isSaving else { return }
        isSaving = true
        isConfirmingDeletion = false

        Task {
            do {
                try await viewModel.deleteTask(id: task.id)
                dismissEditor()
            } catch {
                errorTitle = "Couldn't Delete Task"
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }

    private func dismissEditor() {
        viewModel.selectedTask = nil
        dismiss()
    }

    private func syncTitle(for task: BoardTask) -> String {
        switch task.syncState {
        case .pending:
            "Pending sync"
        case .synced:
            "Synced"
        case .failed:
            "Sync failed"
        }
    }

    private func syncIcon(for task: BoardTask) -> String {
        switch task.syncState {
        case .pending:
            "arrow.triangle.2.circlepath"
        case .synced:
            "checkmark.circle"
        case .failed:
            "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        }
    }

    private func syncColor(for task: BoardTask) -> Color {
        switch task.syncState {
        case .pending:
            .secondary
        case .synced:
            .green
        case .failed:
            .red
        }
    }
}

#Preview("Edit Task") {
    NavigationStack {
        TaskEditorView(
            viewModel: KanbanViewModel(tasks: []),
            task: BoardTask(
                title: "Prepare release notes",
                details: "Summarize the board and offline sync changes.",
                status: .done,
                syncState: .synced
            )
        )
    }
}
