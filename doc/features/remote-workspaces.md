# Remote Workspaces

## Concepts

**Workspace** — a remote machine (e.g. EC2 instance via Coder). Long-lived, provisioned once, shared across multiple worktrees. Identified by a name (e.g. `flight-soft-gem-62ea`).

**Worktree** — a session/branch running on a workspace. Each worktree has its own conversation with Claude. Multiple worktrees can run on the same workspace simultaneously.

**Local worktree** — 1:1 with a git worktree directory on your Mac. No workspace concept. Provisioned via `git worktree add`, torn down via `git worktree remove`.

**Remote worktree** — many-to-one with a workspace. Connected via SSH tunnel (e.g. `coder ssh {workspace} --`). Claude runs on the remote machine.

## Data Model

```
Project
  ├─ remoteMode: RemoteModeConfig?    ← per-project, not global
  │
  ├─ Worktree (local)
  │    ├─ branch: "flight/cool-fox-a3b2"
  │    ├─ path: "~/flight/worktrees/mirage/flight/cool-fox-a3b2"
  │    ├─ isRemote: false
  │    └─ conversations: [Conversation]
  │
  ├─ Worktree (remote, provisioned)
  │    ├─ branch: "flight/wild-fin-97af"
  │    ├─ workspaceName: "flight-wild-fin-97af"  ← shared across worktrees
  │    ├─ isRemote: true
  │    └─ conversations: [Conversation]
  │
  └─ Worktree (remote, attached to same workspace)
       ├─ branch: "flight-wild-fin-97af"
       ├─ workspaceName: "flight-wild-fin-97af"  ← same workspace as above
       ├─ isRemote: true
       └─ conversations: [Conversation]
```

Key relationship: multiple worktrees can share a `workspaceName`. The workspace (machine) is only torn down when the last worktree referencing it is removed.

## Config

Remote mode is configured **per project** in `~/flight/config.json`:

```json
{
  "projects": [
    {
      "id": "...",
      "path": "/Users/nick/code/mirage/mirage",
      "remoteMode": {
        "provision": "~/flight/flight-provision {branch}",
        "connect": "coder ssh {workspace} --",
        "teardown": "coder delete {workspace} --yes",
        "list": "~/flight/flight-list"
      },
      "worktreeConfigs": [...]
    },
    {
      "id": "...",
      "path": "/Users/nick/code/nickdirienzo/flight",
      "worktreeConfigs": [...]
    }
  ]
}
```

- `provision` — runs on new workspace creation. `{branch}` substituted. Must print workspace name as last line of stdout.
- `connect` — SSH tunnel prefix. `{workspace}` substituted. Prepended to the claude command.
- `teardown` — runs when last worktree on a workspace is removed. `{workspace}` substituted.
- `list` — optional. Prints one running workspace name per line. Populates the attach picker.

Different projects can use different infra (Coder, DGX Spark, etc.) or have no remote mode at all.

Configurable via Settings > Remote tab (project picker) or by editing the config file directly.

## Flows

### 1. Provision new workspace (Shift+Cmd+N → "New")

1. User types a prompt, selects "New"
2. Flight generates a random branch name (`flight/calm-owl-a3b2`)
3. Worktree appears immediately in sidebar with "creating" status
4. Runs `provision` command, streaming output to chat UI as system messages
5. Provision script outputs workspace name as last line of stdout
6. Flight captures workspace name, builds connect prefix from `connect` template
7. Spawns Claude via `{connect prefix} claude -p --output-format stream-json ...`
8. Sends initial prompt to Claude

### 2. Attach to existing workspace (Shift+Cmd+N → select workspace)

1. Dialog shows running workspaces (fetched via `list` command) as selectable chips
2. User picks a workspace and types a prompt
3. Flight creates a new worktree entry pointing at that workspace (no provisioning)
4. Spawns Claude via connect prefix — fresh session (no `--resume`)
5. Sends initial prompt to Claude

This lets you run multiple independent Claude sessions on the same machine.

### 3. Remove remote worktree

1. Stop agent(s), clean up conversations/chat history
2. Check if any OTHER worktrees across all projects reference the same `workspaceName`
3. If yes — just remove the worktree entry (workspace stays running for other worktrees)
4. If no — run `teardown` command to destroy the workspace

## Provision Script Protocol

The provision script must:
- Accept the branch name as its argument (substituted from `{branch}`)
- Stream progress to stdout (Flight displays each line in the chat UI as system messages — UI only, not sent to Claude's context)
- Print the workspace name as the **last line** of stdout (Flight captures this)
- Exit 0 on success, non-zero on failure
- Handle its own error cases (CLI not installed, not authed, etc.)

Flight does NOT manage timeouts — the script runs until it completes or is cancelled (via Task cancellation, which sends SIGTERM to the process).

## List Script Protocol

The list script must:
- Print one workspace name per line to stdout
- Only include workspaces that are ready to connect to
- Exit 0 (empty output is fine — means no running workspaces)

Flight is backend-agnostic — it doesn't know about Coder, AWS, or any specific infra. The scripts are the abstraction layer.

## UI

### Sidebar
- Remote worktrees show a cloud icon
- Multiple worktrees on the same workspace are independent entries
- Status indicators work the same (idle/working/ready/error)
- Per-project `+` button creates local worktrees; Shift+Cmd+N for remote

### Shift+Cmd+N Dialog
- Only enabled when the selected project has `remoteMode` configured
- Top: workspace selector — "New" chip (default) + chips for each running workspace from `list` command
- Middle: prompt text editor (multiline, Cmd+Enter to submit)
- Bottom: "Launch" (new) or "Connect" (existing) button
- Workspaces scoped to the selected project's `list` command

### Settings > Remote Tab
- Project picker at top — each project configured independently
- Provision, Connect, Teardown, List (optional) fields
- Save/Remove buttons per project

### Chat
- Provisioning progress streams as system messages (UI-only, not sent to Claude)
- "Connecting to {workspace}..." message on attach
- "Workspace {name} ready. Connecting agent..." on provision complete
