import SwiftUI
import AppKit
import FlightApp

/// The actual @main entry point. Kept intentionally tiny so the bulk of
/// the app lives in the `FlightApp` library target — which the test
/// target imports for NSHostingView-driven UI tests.
@main
struct Flight: App {
    @State private var state = AppState()

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [state] _ in
            state.stopAllAgents()
        }
        NotificationService.requestPermission()
    }

    @State private var themeManager = ThemeManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView(state: state)
                .environment(\.theme, themeManager.currentColors)
                .preferredColorScheme(themeManager.currentColorScheme)
        }

        Settings {
            SettingsView(state: state)
        }
        .commands {
            FlightAppCommands(state: state)
        }
    }
}
