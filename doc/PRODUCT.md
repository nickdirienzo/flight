# Flight — Product Scope

This is the contract for what Flight does and, more importantly, what it
doesn't. Before adding a feature, check it against the scope and the
expansion test below. Drift shows up as remote flakiness, shipped-on-the-side
abstractions, and features that duplicate tools the user already has.

## What Flight is

Flight is an **agent orchestrator**. It owns exactly two things:

1. The **agent conversation loop** — spawning `claude -p` processes, streaming
   their output, routing control requests (permissions, sandbox network
   approvals), managing turn boundaries, persisting transcripts.
2. The **worktree lifecycle** — cutting local git worktrees and provisioning
   remote workspaces through user-supplied `.flight/` scripts. Tearing them
   down when you're done.

That's the whole job.

## What Flight is not

Flight does not build, and will not grow:

- **File tree sync** — no "upload your repo to the remote machine" logic. The
  repo is already on the remote machine, cloned by the provision script, or
  there is no remote machine and the repo is here locally.
- **LSP proxying** — no bridge between the local editor's language server and
  a remote toolchain.
- **Terminal emulation** — no embedded terminal pane. Terminal emulators are a
  deep, well-solved problem with dedicated apps that beat anything we would
  build.
- **Diff viewers** — no inline diff UI for agent-authored changes. The agent
  already summarizes its edits in the transcript; for real review, open the
  worktree in your editor or on the forge.
- **Code review UI** — no PR browser, no review flow. `gh`, the forge's web UI,
  and the editor handle this.
- **Repo management** — no clone, no push, no branch operations beyond
  `git worktree add` / `worktree remove`. The user's shell owns git.

## The escape hatches are the feature

Flight's power comes from handing off to tools that already do their job well:

- **`Cmd+Shift+R`** opens the remote SSH connection in the user's terminal
  emulator (Ghostty, iTerm2, Terminal.app — configurable). The user keeps
  their shell, their scrollback, their keybindings.
- **VS Code Remote-SSH** opens the worktree for editing — local path for
  local worktrees, `ssh-remote+<target>` for remote. Flight provides the
  target and the path; VS Code does everything else.
- **`gh`** handles PR creation, CI triage, issue management. Flight surfaces
  the PR number and check status in the chat header, then gets out of the
  way.

Flight has no opinion on any of these. Swap Ghostty for iTerm2, VS Code for
Cursor, `gh` for `tea` — Flight only knows "run this command when the user
presses the button."

## Remote reliability comes from scope containment

Remote development is hard when it's a distributed system: language server
protocol over a fragile tunnel, a heavy agent binary that has to match the
remote OS, heartbeat protocols that paper over flaky networks.

Flight's remote is reliable because it isn't a distributed system. It's a
process runner with a streaming UI:

- **No binary to upload.** `claude` is already installed on the remote by the
  provision script. The Mac app only runs `ssh <host> claude -p <prompt>`.
- **No heartbeat protocol.** Each turn is a fresh SSH invocation. If it dies,
  the next turn reconnects. There's no long-lived session state to corrupt.
- **No LSP proxy.** The agent runs next to its own toolchain on the remote
  filesystem; nothing has to traverse the network.
- **Backend-agnostic.** `.flight/provision`, `.flight/connect`,
  `.flight/teardown`, `.flight/list` are user-supplied shell scripts. Flight
  doesn't care whether "provision" means `coder create`, `aws ec2 run-instances`,
  `tailscale up`, or `echo $STATIC_HOSTNAME`.

Scope containment is what makes the SSH boundary thin enough to be reliable.
Every feature that crosses the boundary in a richer way (state sync,
persistent sessions, LSP) widens it and makes it flakier.

## The expansion test

Before adding a feature, ask:

> **Does this require Flight to own state that a better standalone tool
> already owns?**

If **yes**, don't add it. Add an escape hatch to the tool that already owns
the state.

Examples:

- "Should Flight render diffs?" → No. The editor renders diffs.
- "Should Flight embed a terminal?" → No. The terminal emulator renders
  terminals. Add a button that launches it (`Cmd+Shift+R`).
- "Should Flight browse PRs?" → No. `gh pr view --web` browses PRs. Expose
  the PR URL and let the user click.
- "Should Flight sync files to a remote?" → No. `rsync`, `mutagen`, `git
  push`, or the provision script owns files on the remote.
- "Should Flight manage remote workspaces directly (EC2 API, Coder API)?"
  → No. The user's `.flight/provision` script owns workspace lifecycle.
- "Should Flight stream the agent's stdout in a nice UI?" → **Yes.** This is
  the core loop; no standalone tool owns it.
- "Should Flight resume a previous `claude` session across app restarts?"
  → **Yes.** The agent-loop is Flight's state, and `--resume <session_id>`
  is how it's resumed.

When in doubt, lean toward the escape hatch. A button that launches
`$TERMINAL_EMULATOR` is a line of code; a built-in terminal is a year of
maintenance.

## What this means for contributors

- A PR that adds a diff viewer, a file tree, a terminal pane, an LSP bridge,
  or a cloud-provider-specific provisioning UI is out of scope. Open an issue
  first; the right answer is probably an escape hatch to a tool that already
  does it.
- A PR that improves the agent loop (streaming, session resume, permission
  handling, transcript persistence) or the worktree lifecycle (provision
  scripts, teardown, remote-only projects) is in scope.
- A PR that ties Flight to a specific forge, VM provider, editor, or terminal
  is out of scope. Flight is backend-agnostic by design.
