# ADR-0005: Aggressive compiler, lint and CI policy

## Status
Accepted

## Date
2026-10-27

## Context
The code is largely AI-written. The cheapest place to catch its typical defects is the compiler and lints:
- panics: unwrap, indexing, string slicing
- silently dropped errors and futures
- locks held across `.await`
- lossy numeric casts
- wildcard matches over enums
- lints silenced without a reason

Noise from extra lints costs little when an agent fixes it.

## Decision
Adopt [docs/quality-policy.md](../quality-policy.md):
- **Rustc:** strict rustc lints.
- **Clippy groups:** `all`, `pedantic`, `nursery` and `cargo` all **denied**.
- **Restriction picks** for panics, silent failures, async, numbers and hygiene.
- **Suppressions:** `#[allow]` is banned in favour of `#[expect(lint, reason = "...")]`.
- **Release profile:** `overflow-checks` stay on in release.
- **Toolchain:** pinned.
- **CI gates:**
  - fmt
  - clippy `-D warnings`
  - workspace lint inheritance
  - tests
  - a coverage floor
  - mutation testing (cargo-mutants)
  - cargo-deny
  - cargo-machete

## Alternatives Considered
- **Clippy defaults with `-D warnings`:** misses the panic, cast and silent-failure classes.
- **A curated subset only:** less noise, but fewer tripwires for future changes.

## Consequences
- **Verified on clippy 1.99.1:** a clean file passes; a file with 18 planted mistakes fails with 30 distinct lints.
- **Known friction:**
  - `clippy::redundant_pub_crate` conflicts with rustc's `unreachable_pub`, so it is allowed with a reason.
  - The `cargo` group requires full package metadata.
  - Proc-macro-heavy UI frameworks can trigger `unused_qualifications`. This is part of why [ADR-0006](0006-leptos-for-the-web-ui.md) chose Leptos.
- **Weakening the policy is itself a reviewed decision.**
