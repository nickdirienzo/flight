import SwiftUI
import AppKit
import FlightApp
#if !DEBUG
import Sentry
#endif

/// The actual @main entry point. Kept intentionally tiny so the bulk of
/// the app lives in the `FlightApp` library target — which the test
/// target imports for NSHostingView-driven UI tests.
@main
struct Flight: App {
    @State private var state = AppState()

    init() {
        #if !DEBUG
        SentrySDK.start { options in
            options.dsn = "https://eaaab6f9b42c992322250844c6ee6c8f@o4506119898923008.ingest.us.sentry.io/4511293130211328"
            options.sendDefaultPii = true
        }
        #endif

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
