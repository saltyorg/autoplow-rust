# ADR-0002: Go as implementation language

## Status
Superseded by [ADR-0004](0004-rust-as-implementation-language.md)

## Date
2026-10-25

## Context
rclone is written in Go, and [ADR-0001](0001-embed-rclone-in-process.md) required embedding it. Most Saltbox tooling is Go. Go also has strong libraries for Google Drive and the Arr apps, and builds static binaries easily.

## Decision
Implement Autoplow in Go.

## Alternatives Considered
- **Rust:** would need a cgo c-archive to embed rclone.

## Consequences
- Superseded once [ADR-0003](0003-rclone-as-supervised-rcd.md) removed the embedding constraint, and once the project prioritised compile-time guarantees for AI-written code.
