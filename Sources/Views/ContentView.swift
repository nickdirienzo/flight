import SwiftUI

struct ContentView: View {
    @Bindable var state: AppState
    @Environment(\.theme) private var theme

    private var selectedWorktree: Worktree? {
        guard let id = state.selectedWorktreeID else { return nil }
        for project in state.projects {
            if let wt = project.worktrees.first(where: { $0.id == id }) {
                return wt
            }
        }
        return nil
    }

    var body: some View {
        HSplitView {
            SidebarView(state: state)
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 300)
                .background(theme.sidebar)

            Group {
                if let worktree = selectedWorktree {
                    ChatView(state: state, worktree: worktree)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 40))
                            .foregroundStyle(theme.secondaryText)
                        Text("No Worktree Selected")
                            .font(.title2)
                            .foregroundStyle(theme.text)
                        Text("Add a repo and create a worktree to get started.")
                            .font(.callout)
                            .foregroundStyle(theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.background)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .alert("Error", isPresented: $state.showingError) {
            Button("OK") {}
        } message: {
            Text(state.errorMessage ?? "An unknown error occurred.")
        }
        .fileImporter(
            isPresented: $state.showingAddRepo,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                state.addProject(path: url.path)
            }
        }
        .sheet(isPresented: $state.showingRemotePrompt) {
            RemotePromptSheet(state: state)
        }
    }
}

struct RemotePromptSheet: View {
    @Bindable var state: AppState
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("New Remote Worktree")
                .font(.headline)

            Text("What should the agent work on?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: $state.remoteInitialPrompt)
                .font(.system(size: 13))
                .frame(width: 450, height: 120)
                .focused($isFocused)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Launch") { launch() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(state.remoteInitialPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .onAppear { isFocused = true }
    }

    private func launch() {
        let prompt = state.remoteInitialPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        state.remoteInitialPrompt = ""
        dismiss()
        Task {
            await state.createRemoteWorktree(initialPrompt: prompt)
        }
    }
}
