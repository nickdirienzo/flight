import Foundation

/// Static catalog of Claude models selectable from the input bar.
///
/// Source of truth: Claude Code release notes / Anthropic model docs. When
/// new models ship, add entries here. This list is intentionally small —
/// the CLI has no `claude models list` command, and hitting the Anthropic
/// `/v1/models` API on launch isn't worth the auth/caching complexity for
/// a list that changes a few times per year.
///
/// `id` is passed verbatim to `claude --model`. The `[1m]` suffix selects
/// the 1M-context variant of a base model (confirmed working for
/// `claude-opus-4-6[1m]`; add other 1M variants only after verifying the
/// CLI accepts them).
public enum ModelCatalog {
    public struct Entry: Identifiable, Hashable {
        public let id: String      // CLI-accepted model ID
        public let label: String   // Shown in the menu

        public init(id: String, label: String) {
            self.id = id
            self.label = label
        }

        public var hasExtendedContext: Bool { id.hasSuffix("[1m]") }
    }

    public struct Family: Identifiable, Hashable {
        public let id: String      // "opus" / "sonnet" / "haiku"
        public let label: String
        public let entries: [Entry]

        public init(id: String, label: String, entries: [Entry]) {
            self.id = id
            self.label = label
            self.entries = entries
        }
    }

    public static let families: [Family] = [
        Family(id: "opus", label: "Opus", entries: [
            Entry(id: "claude-opus-4-7",      label: "Opus 4.7"),
            Entry(id: "claude-opus-4-7[1m]",  label: "Opus 4.7 (1M)"),
            Entry(id: "claude-opus-4-6",      label: "Opus 4.6"),
            Entry(id: "claude-opus-4-6[1m]",  label: "Opus 4.6 (1M)"),
            Entry(id: "claude-opus-4-5",      label: "Opus 4.5"),
        ]),
        Family(id: "sonnet", label: "Sonnet", entries: [
            Entry(id: "claude-sonnet-4-6", label: "Sonnet 4.6"),
            Entry(id: "claude-sonnet-4-5", label: "Sonnet 4.5"),
        ]),
        Family(id: "haiku", label: "Haiku", entries: [
            Entry(id: "claude-haiku-4-5", label: "Haiku 4.5"),
        ]),
    ]

    public static func entry(forID id: String) -> Entry? {
        for family in families {
            if let match = family.entries.first(where: { $0.id == id }) {
                return match
            }
        }
        return nil
    }

    public static func label(forID id: String) -> String {
        entry(forID: id)?.label ?? id
    }
}
