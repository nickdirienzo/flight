import SwiftUI

public struct ContentView: View {
    @Bindable var state: AppState
    @Environment(\.theme) private var theme

    public init(state: AppState) {
        self.state = state
    }

    private var selectedWorktree: Worktree? {
        guard let id = state.selectedWorktreeID else { return nil }
        for project in state.projects {
            if let wt = project.worktrees.first(where: { $0.id == id }) {
                return wt
            }
        }
        return nil
    }

    public var body: some View {
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
        .sheet(isPresented: $state.showingAddProjectSheet) {
            AddProjectSheet(state: state)
                .environment(\.theme, theme)
        }
        .sheet(isPresented: $state.showingProjectPicker) {
            ProjectPickerSheet(state: state)
                .environment(\.theme, theme)
        }
    }
}

