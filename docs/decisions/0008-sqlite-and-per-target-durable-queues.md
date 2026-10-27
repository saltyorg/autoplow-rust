# ADR-0008: SQLite storage with per-target durable queues

## Status
Accepted

## Date
2026-10-25

## Context
Predecessors lost work in several ways:
- in-memory channels that dropped items when full
- a shared runner where one slow target blocked all the others
- workers that stopped for good after a fatal error
- caches that never refreshed

autoscan's per-target queues with a generation-acknowledged delete, and autopulse's database-enforced dedup and compare-and-set status writes, both worked well (see `docs/research/`).

## Decision
- **Store:** SQLite (rusqlite, bundled) in WAL mode, with one writer and a reader pool, and versioned, tested migrations.
- **One durable queue per target**, keyed on (target, folder):
  - a generation counter; acknowledgement deletes a row only if its generation is unchanged, so an event that arrives after dispatch always causes another scan
  - a unique partial index on pending entries, written with an upsert
  - compare-and-set status updates
  - FIFO by ready time
- **Errors are classified:** retry, back off the target, or dead-letter the path. A worker never dies because of one path.
- **Intake** applies back-pressure instead of dropping work.

## Alternatives Considered
- **One shared runner and retry clock** (autopulse): no isolation between targets.
- **Postgres:** unnecessary for a single-node daemon.

## Consequences
- SQLite needs a C toolchain for cross builds.
- The schema is the contract for queue semantics and is covered by migration tests.
