# ADR-0006: Leptos (client-side WASM) for the web UI

## Status
Accepted

## Date
2026-10-27

## Context
The UI is a single-page app that uses only the public REST API and SSE ([ADR-0007](0007-seed-once-bootstrap-and-rest-api.md)), and it is embedded in the binary. A Rust UI can share the backend's API types, so a breaking API change fails the UI build.

A spike built the same page (login, a queue list, live SSE updates) in Leptos 0.8 and Dioxus 0.7. Both were built under the full lint policy and both pass a Playwright test:

| | Leptos | Dioxus |
|---|---|---|
| WASM after `wasm-opt -Oz` | 197 KB (83 KB gzip) | 694 KB (234 KB gzip) |
| Build (cold / incremental) | 32 s / 5 s | 31 s / 8 s |
| Lint friction | none from the framework | `rsx!` event handlers trigger `unused_qualifications` on every interactive component |

## Decision
Use **Leptos** in CSR mode, built with trunk with `wasm-opt -Oz` enabled, and embedded with rust-embed. API types live in a crate shared with the backend. End-to-end UI tests use **Playwright**.

## Alternatives Considered
- **Dioxus:** largest community, but about 2.8x the download, recurring lint exceptions, and frequent breaking releases.
- **Yew:** slowing release cadence.
- **Sycamore:** small community.
- **egui and Iced:** canvas or native-first, so a poor fit for an accessible web admin.
- **Server-rendered templates (Askama or Maud with htmx):** conflict with "the UI uses only the public API". The predecessor drifted into business logic in handlers this way.
- **A JavaScript SPA (Svelte or React):** loses the shared compile-checked types.

## Consequences
- **Bundle:** about 83 KB of gzipped WASM for a small page.
- **Components:** fewer ready-made UI components than JavaScript ecosystems.
- **Build:** trunk and wasm tooling in CI.
