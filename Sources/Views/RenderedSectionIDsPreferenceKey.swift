import SwiftUI
import FlightCore

/// Each rendered chat section bubbles its UUID up through this preference
/// key. SwiftUI accumulates them via `reduce` so the parent sees the full
/// list of *realized* (LazyVStack-materialized) section IDs in document
/// order. Production code has no observer; the rendering test suite uses
/// `onPreferenceChange` to verify the realized set never escapes the
/// paginated window.
public struct RenderedSectionIDsPreferenceKey: PreferenceKey {
    public static let defaultValue: [UUID] = []
    public static func reduce(value: inout [UUID], nextValue: () -> [UUID]) {
        value.append(contentsOf: nextValue())
    }
}
