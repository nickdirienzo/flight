# ADR-003: No built-in terminal emulator

## Status

Accepted. Reflects current implementation: `Cmd+Shift+R` in
`Sources/FlightApp.swift` calls `openRemoteSession` in `AppState.swift`,
which runs the remote `claude` session through the user's terminal.

## Context

Remote worktrees sometimes need interactive shell access — to tail a log,
run an ad-hoc command, or drop into an interactive `claude` session that's
visible in the Claude Code mobile app. Flight could:

1. Embed a terminal pane (via SwiftTerm or similar) inside the app window.
2. Open the remote SSH connection in the user's system terminal emulator.

## Decision

**`Cmd+Shift+R` opens the remote SSH connection in the system terminal
emulator.** The user's default terminal handles the session (Terminal.app
out of the box; Ghostty, iTerm2, Warp, Alacritty, anything else when
configured as default). Flight does not embed a terminal pane.

A visible button in the chat header mirrors the shortcut so the escape
hatch is discoverable without opening the keyboard-shortcut list.

## Rationale

- **Terminal emulators are a deep, well-solved problem.** Ghostty, iTerm2,
  kitty, Alacritty, WezTerm, and Terminal.app have collectively spent
  decades on font rendering, GPU acceleration, SGR escape handling, tmux
  integration, pane/tab UX, OSC 52 clipboard, Sixel graphics, keybinding
  customization, profile management, and platform-specific polish. Anything
  we embed would be worse on every axis.
- **The user already has their terminal configured.** Themes, fonts,
  keybindings, shell integrations, clipboard rules. Hijacking them into a
  second, lesser terminal inside our window is hostile.
- **Embedded terminals are a maintenance surface with no agent-loop
  benefit.** They pull in a large dependency, add platform-specific bugs,
  and require tracking upstream changes in whichever terminal library we
  pick. None of that work makes the agent loop better.
- **Flight's escape-hatch model (ADR-adjacent to scope doc).** The whole
  product stance (see `doc/PRODUCT.md`) is: hand off to tools that already
  do their job well. Terminal emulation is the canonical example of a job
  that's already done.
- **Cheap to extend.** The shortcut shells out to a configurable command —
  defaults to `open -a Terminal` for Terminal.app, users can point it at
  Ghostty or iTerm2 via settings. No code changes required per emulator.

## Rejected alternative: embedded terminal pane

- Large dependency (SwiftTerm or equivalent) to maintain.
- Inferior to any dedicated terminal on every measurable axis.
- Multiplies the support surface: "why doesn't my tmux 256-color scheme
  render in Flight's terminal" is a class of issue we'd inherit.
- Makes the app's window layout more complex for a feature that belongs
  in a separate window anyway.

## Consequences

- Users without a preferred terminal configured get Terminal.app, which is
  reasonable default behavior on macOS.
- Features that would need the embedded terminal (inline command suggestions,
  tight coupling between chat and shell) have to be designed differently —
  either as escape hatches (`gh pr checkout`, `open in VS Code`) or not at
  all.
- The terminal-emulator choice is fully the user's. Flight doesn't need to
  track terminal-emulator changes, updates, or quirks.
- `Cmd+Shift+R` opens the remote session via tmux so the interactive
  `claude` process survives the SSH connection and remains visible in the
  Claude Code mobile app.
