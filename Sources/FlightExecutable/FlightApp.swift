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
        // Pre-warm the login-shell PATH capture before any agent/shell
        // spawn so the first turn doesn't pay the ~50–200ms cost.
        _ = EnvironmentService.path

        #if !DEBUG
        SentrySDK.start { options in
            options.dsn = "https://eaaab6f9b42c992322250844c6ee6c8f@o4506119898923008.ingest.us.sentry.io/4511293130211328"
            options.sendDefaultPii = true

            // Hang reports landed in os_diag but never made it to Sentry on
            // a force-quit. Be explicit about hang tracking so default drift
            // across SDK versions doesn't silently turn it off, and bump the
            // threshold to 5s so we catch the real hangs (>30s in stackshots)
            // without spamming on transient main-thread blocks.
            options.enableAppHangTracking = true
            options.appHangTimeoutInterval = 5

            // Tag events with version so a single noisy build is filterable
            // in Sentry's UI; without this every event coalesces into one
            // unversioned bucket.
            let info = Bundle.main.infoDictionary
            let short = info?["CFBundleShortVersionString"] as? String ?? "unknown"
            let build = info?["CFBundleVersion"] as? String ?? "0"
            options.releaseName = "ai.miragesecurity.flight@\(short)+\(build)"
        }
        SentryService.subprocessFailureHandler = { command, exitCode, correlationID in
            SentrySDK.capture(message: "Subprocess '\(command)' exited \(exitCode)") { scope in
                scope.setTag(value: command, key: "subprocess.command")
                scope.setTag(value: String(exitCode), key: "subprocess.exit_code")
                scope.setExtra(value: correlationID, key: "correlation_id")
            }
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
