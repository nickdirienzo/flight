# Flight

A Mac-native GUI for orchestrating parallel Claude Code agents across local git worktrees and remote workspaces.

Built as an internal tool for daily agentic coding work. Open-sourced so others can adapt it.

![Remote provisioning](doc/images/remote-provisioning.png)

## What it does

- Manage multiple git repos in a sidebar, switch between projects with a fuzzy picker (Cmd+N / Cmd+Shift+N)
- Spin up isolated git worktrees per task, each running its own Claude Code agent
- Chat with agents in a streaming UI with collapsible tool calls and markdown rendering
- Run agents locally (sandboxed) or remotely via SSH (e.g. Coder, EC2, any machine)
- Open worktrees directly in VS Code — local paths or through Remote-SSH for remote workspaces
- Per-worktree PR creation, CI check status, reviewer feedback (GitHub and Forgejo)
- Multiple conversations per worktree with tab support
- Base16 theme engine with 6 built-in themes + import support

## Install

Requires macOS 14+ and Swift 5.9+. No Xcode needed.

```bash
git clone https://github.com/mirage-security/flight.git
cd flight
./build.sh
open Flight.app
```

Or run directly:

```bash
swift run Flight
```

### Prerequisites

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) (`claude`) on your PATH
- [GitHub CLI](https://cli.github.com/) (`gh`) for PR/CI features (optional)

## Usage

### Local worktrees

1. Click **Add Repo** to add a git repository
2. **Cmd+N** creates a new worktree with a random branch name and starts a Claude agent
3. Chat in the input bar, hit **Enter** to send
4. **Escape** interrupts the agent mid-turn

### Remote workspaces

1. Drop executable lifecycle scripts into `.flight/` in the repo (or configure templates in **Settings > Remote**)
2. **Cmd+Shift+N** opens a project picker → select the project → the remote prompt sheet appears
3. Pick "New" to provision a fresh workspace, or an existing one from the list
4. Type your initial prompt and hit **Cmd+Enter**

Remote mode is backend-agnostic. You provide four scripts in `.flight/` at the repo root:

| Script | Env | Args | Purpose |
|---|---|---|---|
| `.flight/provision` | `FLIGHT_BRANCH` | — | Create a workspace. Prints workspace name as last line of stdout. Can emit `FLIGHT_OUTPUT: key=value` metadata (see below). |
| `.flight/connect` | `FLIGHT_WORKSPACE` | `"$@"` | SSH wrapper. Runs its argv on the remote workspace. e.g. `exec coder ssh "$FLIGHT_WORKSPACE" -- "$@"` |
| `.flight/teardown` | `FLIGHT_WORKSPACE` | — | Destroy the workspace. |
| `.flight/list` | — | — | Optional. Prints running workspace names, one per line. Populates the "attach to existing" picker. |

Scripts run via `zsh -l -c` with cwd at the repo root. Each can also be set as a settings-level template (`Settings > Remote`) which overrides the on-disk script for local iteration.

Example `.flight/provision` for Coder:

```bash
#!/usr/bin/env bash
set -euo pipefail
BRANCH="${FLIGHT_BRANCH:?}"
NAME="$(echo "$BRANCH" | tr '/' '-' | tr -cd 'a-z0-9-')"

echo "Creating workspace '$NAME' on branch '$BRANCH'..."
coder create "$NAME" --template my-template --parameter "git_branch=$BRANCH" --yes

# Metadata — Flight strips these from the displayed log and stores them
# on the worktree. Used by the "Open URL" and "Open in VS Code" buttons.
echo "FLIGHT_OUTPUT: url=https://$NAME.example.com"
echo "FLIGHT_OUTPUT: ssh_target=coder.$NAME"
echo "FLIGHT_OUTPUT: repo_path=/home/ubuntu/my-repo"

# Last non-metadata line is captured as the workspace name
echo "$NAME"
```

And `.flight/connect`:

```bash
#!/usr/bin/env bash
exec coder ssh "${FLIGHT_WORKSPACE:?}" -- "$@"
```

### `FLIGHT_OUTPUT` metadata

Provision scripts can emit `FLIGHT_OUTPUT: key=value` lines anywhere in their stream. Flight parses them out (they don't appear in the UI log) and attaches them to the worktree. Recognised keys:

| Key | Purpose |
|---|---|
| `url` | Browser URL for the workspace (web IDE, dashboard). Shows as a link button in the chat header. |
| `ssh_target` | The value that follows `ssh-remote+` for VS Code Remote-SSH (e.g. `coder.my-workspace`, `user@host`). |
| `repo_path` | Path to the repo checkout on the remote workspace. Used by VS Code Remote-SSH to open the right folder. |

Unknown keys are ignored, so the contract is forward-compatible.

### Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+N | New local worktree (project picker if >1 project) |
| Cmd+Shift+N | New remote worktree (picker over remote-capable projects) |
| Cmd+T | New conversation tab |
| Cmd+W | Close conversation tab (or window if only one tab) |
| Cmd+1-9 | Switch worktrees |
| Cmd+Enter | Restart agent for current worktree |
| Cmd+. | Stop agent |
| Cmd+K | Clear chat |
| Cmd+Shift+R | Open remote session in Terminal (remote worktrees) |
| Cmd+, | Settings |
| Escape | Interrupt agent mid-turn |

### Themes

Flight uses [Base16](https://github.com/tinted-theming/schemes) for theming. Built-in themes:

- System (follows macOS appearance)
- Solarized Dark / Light
- Tokyo Night
- Gruvbox Dark
- Catppuccin Mocha
- Nord

Import any Base16 `.json` theme file via **Settings > General > Import Base16 Theme**. Imported themes are saved to `~/flight/themes/`.

## Architecture

```
Sources/
  FlightApp.swift             App entry, window, keyboard shortcuts
  AppState.swift              Central @Observable state
  Theme.swift                 Base16 theme engine
  Models/
    Project.swift             Repo reference + remote config
    Worktree.swift            Branch, status, conversations, remote metadata
    Conversation.swift        Per-tab agent session
    AgentMessage.swift        Parsed stream-json messages
    PRStatus.swift            PR review state and decision
    CIStatus.swift            CI check state per worktree
  Services/
    ClaudeAgent.swift         Process lifecycle, stdin/stdout, turn management
    ConfigService.swift       ~/flight/config.json persistence
    GitService.swift          git worktree operations
    ShellService.swift        Async process runner with env/extraArgs support
    RemoteScriptsService.swift Resolves .flight/<script> + settings templates
    WorktreeSetupService.swift Runs .flight/worktree-setup for new local worktrees
    NotificationService.swift  macOS user notifications
  Plugins/
    ForgeProvider.swift       Git hosting abstraction
    GitHubForge.swift         GitHub implementation (gh CLI)
    ForgejoForge.swift        Forgejo implementation
  Views/
    ContentView.swift         Main layout, sheets, error alerts
    SidebarView.swift         Project/worktree list
    ChatView.swift            Message list, header, tool groups
    MessageView.swift         Chat bubbles + tool call rows
    MarkdownText.swift        Lightweight markdown renderer
    InputBarView.swift        Text input, plan mode, stop button
    PasteableTextView.swift   NSTextView wrapper for reliable keyboard handling
    ProjectPickerSheet.swift  Command-palette project picker for Cmd+N / Cmd+Shift+N
    SettingsView.swift        Themes, font size, worktree setup, remote config
```

### How agents work

Each user message spawns a new `claude -p` process with `--output-format stream-json`. Subsequent messages use `--resume <session_id>` to maintain conversation context. This one-process-per-turn model avoids the complexity of long-lived bidirectional streaming.

**Local**: Process runs directly with the sandbox enabled (filesystem scoped to the worktree, `dangerouslyDisableSandbox` overrides denied).

**Remote**: Flight invokes `zsh -l -c '<connect command>' _ '<remote claude invocation>'` with `FLIGHT_WORKSPACE` set in the environment. Your `.flight/connect` script receives the claude invocation as `"$@"` and SSHes it to the remote workspace. The initial prompt is base64-encoded through a temp file on the remote for safe shell transport. Remote agents run with `--dangerously-skip-permissions` since the workspace is its own isolation boundary.

### Data storage

All data lives in `~/flight/`:

```
~/flight/
  config.json              Projects, worktrees, remote config
  chat/                    Conversation history (JSON per conversation)
  logs/                    Raw stdin/stdout logs per worktree
  themes/                  Imported Base16 theme files
  worktrees/               Git worktree directories
```

## License

MIT
