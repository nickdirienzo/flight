# ADR-002: Remote execution via user-supplied shell scripts

## Status

Accepted. Reflects the `.flight/` contract documented in the README and
implemented in `Sources/FlightCore/Services/RemoteScriptsService.swift`.

## Context

Flight supports running agents on remote machines — an EC2 instance, a
Coder workspace, a home-lab server reachable over Tailscale, anything with
SSH. The question is how Flight should model the provider.

Options:

1. **Built-in provider plugins.** Ship Swift code that knows how to talk to
   the Coder API, the EC2 API, the Tailscale API, raw SSH, etc. User picks
   a provider from a dropdown and fills in credentials.
2. **One blessed backend.** Pick one (say, Coder) and tie Flight to it.
3. **User-supplied shell scripts.** Flight defines a lifecycle contract
   (`provision`, `connect`, `teardown`, `list`) and invokes user-written
   scripts that speak whatever API they need.

## Decision

**`.flight/provision`, `.flight/connect`, `.flight/teardown`, `.flight/list`
are plain shell scripts the user provides.** Flight shells out to them with
a documented env/argv contract:

- `provision` — `FLIGHT_BRANCH` in env, prints workspace name as last line,
  can emit `FLIGHT_OUTPUT: key=value` metadata.
- `connect` — `FLIGHT_WORKSPACE` in env, argv is the remote command to run
  (SSH wrapper).
- `teardown` — `FLIGHT_WORKSPACE` in env, destroys the workspace.
- `list` — optional, prints running workspace names.

Scripts run via `zsh -l -c` with cwd at the repo root (for local projects)
or `~/flight` (for remote-only).

## Rationale

- **Backend-agnostic by design.** The same Flight binary works with Coder,
  EC2, Tailscale, a static homelab SSH target, a dev-VM-per-branch setup,
  or a shell script that runs `docker run`. No provider lock-in, no
  per-provider maintenance burden on the project.
- **No credentials in Flight.** The scripts use whatever auth mechanism is
  native to the target (Coder session, AWS credentials, SSH keys). Flight
  never sees tokens or keys.
- **User retains full control.** If the user wants their provision script
  to send a Slack notification, tag the VM with their username, or write to
  a team-shared audit log, they just add lines to the script.
- **Onboarding cost matches user's infrastructure complexity.** A user
  with `ssh me@my-homelab` writes a 3-line connect script. A Coder user
  writes the 10-line example from the README. Each gets the setup they'd
  have written anyway.
- **Matches the Unix philosophy.** Provision is a verb the shell has known
  how to do for decades. Don't reinvent it in Swift.

## Rejected alternative: built-in Coder/EC2/SSH provider plugins

- Every new provider is a first-party integration with its own auth flow,
  error handling, rate-limit concerns, SDK update cycle.
- Ties the project's release cadence to third-party API stability.
- Forces a lowest-common-denominator UX: the union of features that every
  plugin implements, nothing provider-specific surfaced cleanly.
- Creates pressure to pick "winners" (which providers are supported?) and
  leaves users on other backends with a second-class experience.

## Consequences

- Users writing their first provision script face a small learning curve.
  Mitigation: the README ships a working Coder example, and the `.flight/`
  script names plus the env-var contract are self-documenting.
- Bad scripts can fail in interesting ways. Flight surfaces the stdout
  stream in the provision UI group so the user can debug in place.
- The `FLIGHT_OUTPUT: key=value` sidechannel is the only extension point.
  New metadata keys can be added without changing the script contract —
  unknown keys are silently ignored, so forward-compat is free.
- Remote-only projects (ADR-004) work the same way: Flight downloads the
  committed scripts from the forge and runs them. The contract is
  independent of whether the scripts live on disk or in a cache.
