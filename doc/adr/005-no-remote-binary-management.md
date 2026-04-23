# ADR-005: Flight never manages remote binaries

## Status

Accepted. Reinforces the scope boundary established in ADR-002 and
`doc/PRODUCT.md`.

## Context

A natural extension to Flight's remote-execution story would be to upload
and manage a small daemon (say, `flight-remote-server`) on each remote
machine automatically. The client could sync binaries on first connect,
check versions, and upgrade when the protocol changes. This is how
editors with rich remote support tend to work — the client pushes a
server-side agent over SSH, keeps it in sync, and talks to it over a
long-lived protocol.

Doing this in Flight would mean owning:

- Architecture detection (arm64 vs x86_64 vs …).
- Binary hosting and distribution.
- Upload-over-SSH with retry on slow links.
- Install-path selection and sudo negotiation on locked-down machines.
- Version negotiation between client and server across releases.
- Self-upgrade flows when the client is newer than what's deployed.

Each of these is a tractable problem in isolation. Together they produce
a class of failure modes that are hard to recover from in the field —
the user sees an unhelpful "failed to connect" message an hour into a
session on a flaky hotel network, and has no clear path back to a
working state.

## Decision

**Flight does not upload, install, update, or version-check any software
on remote machines.** The provision script (`.flight/provision`, per
ADR-002) is the user's responsibility — Flight shells out to it and
trusts the result. Binaries that need to exist on the remote side
(`claude`, `FlightServer`, anything else) are the user's problem to put
there.

The recommended pattern: bake whatever the workspace needs into the
base image (golden AMI, Docker image, Coder template, Packer build,
etc.) so provision just starts the workspace — no upload, no install,
no version negotiation over the wire.

## Rejected alternative: automatic remote server installation

- **Arch mismatches silently break users.** Client running on an M-series
  Mac, remote running on x86_64 — pick the wrong binary and the user sees
  a cryptic `exec format error` on first command, far from the decision
  that caused it.
- **Upload failures on slow connections turn into retry hell.** A 20MB
  binary over a 1MB/s link takes 20 seconds; over hotel Wi-Fi with
  packet loss it can take minutes or never finish. Papering over this
  with resumable uploads and progress UI is a project in itself.
- **Sudo permission issues are unfixable from the client.** If the
  target install path needs sudo and the user hasn't configured
  passwordless sudo for it, there's no good UX to recover. Client-driven
  install becomes "tell the user to SSH in manually and fix it" — which
  is exactly the state we'd have if we'd never tried to auto-install.
- **Version skew introduces coordination bugs.** Client 1.5 with server
  1.3 has to negotiate a protocol subset. Every release adds a
  compatibility matrix. The compatibility matrix eventually has holes.
- **It violates the scope doc.** "Does Flight need to own state that a
  better tool already owns?" The target OS's package manager, the base
  image builder, and the VM provisioner already own binary deployment.
  Duplicating that work inside Flight is exactly the expansion we've
  decided against.

## Consequences

- The user is responsible for ensuring `claude` (and optionally
  `FlightServer`) are installed on the remote workspace before
  `.flight/connect` runs commands there.
- Onboarding for net-new users includes "get `claude` into your base
  image." This is a one-time step for most deployments; for Coder/EC2
  workflows it maps naturally onto the existing image-building process.
- **FlightServer's HTTP/SSE transport removes the need for a persistent
  SSH tunnel during agent execution.** SSH is used exactly once, at
  provision time, and optionally for the `Cmd+Shift+R` terminal
  handoff. After provision, HTTP handles reconnection, proxying, and
  transport for all chat traffic — more robust for long-running agent
  turns that may outlive a network hiccup.
- Version skew between client and `FlightServer` is avoided the
  old-fashioned way: ship the same version, commit the image. Users who
  want to pin a specific server version do so in their Dockerfile, not
  in a Flight setting.

## One-line summary

The provision script is your Dockerfile. Flight is just `docker run`.
