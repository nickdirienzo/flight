# ADR-001: One-process-per-turn agent model

## Status

Accepted. Reflects current implementation in `Sources/FlightCore/Services/ClaudeAgent.swift`.

## Context

Flight needs to run `claude` as a subprocess and stream its stream-json output
into the chat UI. There are two ways to structure the process lifecycle:

1. **One long-lived process per conversation.** Spawn `claude` once, hold
   stdin open, feed each user message as a new `{"type":"user", ...}` line.
   Tear down when the conversation closes.
2. **One process per turn.** Spawn a fresh `claude -p` for each user message.
   The first turn establishes the session ID; subsequent turns pass
   `--resume <session_id>` to pick up where the previous one left off.

The long-lived model sounds more efficient on paper — no repeated process
startup — but it forces Flight to own a bunch of protocol state that claude
and the OS already know how to track.

## Decision

**Each user message spawns a new `claude -p` process. Subsequent messages
use `--resume <session_id>`.**

The session ID is emitted by claude on the first `system` event of each run
and persisted on the `Conversation`. Interrupt = SIGINT on the current turn
process. Tab close = `stop()` on the agent, which terminates the process and
closes its pipes.

## Rationale

- **Simpler lifecycle.** A process that exists for exactly one turn has one
  termination condition: the `result` event lands, the process exits, we
  clear `isBusy`. No reconnection, no zombie detection, no "is the pipe
  still alive" heartbeat.
- **No zombie handling.** Long-lived processes under launchd accumulate when
  parents crash. We've seen a dozen claude processes pile up for one session
  in the long-lived model. One-process-per-turn is naturally bounded: at
  most one process per conversation, always terminable.
- **HTTP-friendly for FlightServer.** An HTTP request maps 1:1 onto a turn.
  `POST /sessions/:id/chat` becomes "spawn one `claude --resume ...`, stream
  its output, close the connection when it exits." No session affinity
  between requests; any FlightServer instance can serve any chat request.
- **Turn boundaries are natural crash recovery points.** If the app (or the
  remote SSH tunnel) dies mid-turn, the next turn is a fresh process with
  `--resume` — claude's own session jsonl is the source of truth for
  history, and Flight just reconnects to it.
- **No stdin framing state.** We don't have to track "did the last message
  end in a newline," "is there a pending partial line," etc. Each turn's
  stdin is exactly one JSON payload.

## Rejected alternative: long-lived bidirectional streaming process

- Requires Flight to own framing, reconnection, and recovery logic that
  claude already handles via `--resume`.
- Zombie-process handling becomes a recurring debug burden.
- Does not compose cleanly with an HTTP server — either the HTTP handler
  blocks a worker thread for the lifetime of the conversation, or we invent
  our own session-affinity routing on top.
- Process startup cost is ~50-100ms. For interactive chat, this is well
  below the perception threshold, so we're optimizing the wrong thing.

## Consequences

- Each turn pays process startup cost. Acceptable: startup is faster than
  the first token from the model.
- Session ID must be persisted across app restarts so `--resume` works.
  Handled via `ConversationConfig.sessionID` in `config.json`.
- Interrupting a turn means SIGINT on the current process. The `--resume`
  on the next turn picks up from wherever claude had flushed its jsonl.
- Control requests (permission prompts, sandbox network approvals) are
  answered via `control_response` written back to the current turn's stdin.
  This only works while the turn is live, which is fine because that's
  when claude needs the answer.
