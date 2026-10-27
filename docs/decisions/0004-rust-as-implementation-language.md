# ADR-0004: Rust as implementation language

## Status
Accepted (supersedes [ADR-0002](0002-go-as-implementation-language.md))

## Date
2026-10-27

## Context
- Autoplow will be largely AI-written. Runtime failures often seen in AI-written code (panics, nil dereferences, unchecked errors, data races) become compile-time errors in Rust, especially with strict lints ([ADR-0005](0005-aggressive-quality-policy.md)).
- With rclone out of process ([ADR-0003](0003-rclone-as-supervised-rcd.md)), Rust needs no cgo.
- A survey (see `docs/research/rust-vs-go.md`) found:
  - **Go is stronger on:** Google Drive and OAuth libraries, Arr and media-server clients, static cross builds, and SQLite without a C dependency.
  - **Rust is stronger on:** typed config and schema (serde, schemars, serde-saphyr) and recursive file watching.
  - **The rest** is roughly equal.

## Decision
Implement Autoplow in Rust: a static musl binary for x86_64 and aarch64, Linux only.

## Alternatives Considered
- **Go:** more ready-made libraries and simpler builds, but weaker compile-time guarantees.

## Consequences
- **Narrow, typed clients are hand-written** for Plex, Jellyfin, Emby, Tofa, the Arrs and Google Drive, each with contract tests against recorded fixtures.
- **Builds are slower**, so CI uses caching and the toolchain is pinned.
- C dependencies (bundled SQLite, the TLS crypto provider) must cross-compile for musl and aarch64 (cargo-zigbuild).
