# ADR-004: Client-side statelessness for remote projects

## Status

Accepted. Reflects the `Project.isRemoteOnly` path in
`Sources/FlightCore/Models/Project.swift` and the forge-fetching logic in
`Sources/FlightCore/Services/RemoteScriptFetcher.swift`.

## Context

Some projects that Flight's users work with aren't on the local machine:

- Company repos with tight data-residency rules (health records, PII,
  customer data) where the code cannot be cloned to a laptop.
- Large monorepos that are impractical to clone on a mobile-class device
  but fine on a 16-core dev VM.
- Private forks hosted on internal Forgejo instances reachable only via
  the company network, from which a personal laptop connects over VPN.
- The on-the-go case: the user is on an iPad or a borrowed machine and
  wants to spin up a remote workspace without cloning.

For these projects, Flight needs to:

1. Know the project's name and forge coordinates (owner/repo).
2. Know how to provision/connect/teardown remote workspaces for it.

Both pieces of info are committed to the repo's `.flight/` directory on
the remote forge. The question is whether Flight needs a local clone to
get at them.

## Decision

**For remote-only projects, the repo is the source of truth for `.flight/`
scripts. No local clone required.** Flight fetches
`.flight/provision`, `.flight/connect`, `.flight/teardown`, and
(optionally) `.flight/list` via the forge API when the project is added,
caches them under `~/flight/remote-scripts/<project-name>/`, and uses
them the same way it uses on-disk scripts for locally-cloned projects.

Settings-level script overrides (from `Settings > Remote`) are ignored
for remote-only projects. If the user wants to change a script, they push
the change to the default branch and re-add the project.

## Rationale

- **Enables mobile / on-the-go use cases.** A user with an iPad or a
  borrowed machine can add a project, spin up a remote workspace, and
  start driving an agent — all without needing `git clone` on the client.
- **Sensitive data never leaves the remote machine.** The workspace VM is
  the only place the source code exists. Flight holds only the scripts
  that orchestrate the VM, not the code itself. This matters for regulated
  environments (HIPAA, SOC 2, internal-only codebases) where cloning
  sensitive code to a personal device is a policy violation.
- **Keeps Flight's disk footprint small.** Adding a project adds ~4KB of
  scripts, not the whole repo.
- **Matches the escape-hatch philosophy.** The forge already owns the
  authoritative `.flight/` scripts. Flight just caches them; it doesn't
  need to re-implement the forge's storage or versioning.
- **Forge-agnostic via a thin fetch layer.** `RemoteScriptFetcher` uses
  `gh api` for GitHub and the Forgejo raw endpoint for Forgejo. New
  forges plug in by adding a new case; everything downstream is identical.

## Rejected alternative: requiring a local clone for every project

- Forces users with policy restrictions to either violate policy or skip
  Flight entirely.
- Inflates disk usage for users who only ever want to drive remote agents.
- Couples project add-time to the user's network path to the git host
  (a fresh clone of a monorepo over VPN is slow enough to feel broken).
- Makes the mobile/iPad story effectively impossible.

## Consequences

- Script updates require a push to the default branch, not a local edit.
  Acceptable — scripts change rarely, and committing them is what we want
  anyway for auditability.
- Cache invalidation is manual (re-add the project). This is a deliberate
  tradeoff: an automatic "refetch on every Flight launch" would make
  startup dependent on forge availability, which is the wrong dependency
  for a local-first app.
- PR/CI features work for remote-only projects too, because
  `ForgeProvider` uses `gh --repo owner/name` (or the Forgejo REST API)
  rather than cwd-in-repo inference. No local checkout needed for PR
  number, review status, or CI check lookups.
- Local and remote-only projects can coexist for the same repo (useful
  for users iterating on `.flight/` scripts locally before committing).
  Name collision is surfaced at add time; the user renames one or the
  other in the add sheet.
