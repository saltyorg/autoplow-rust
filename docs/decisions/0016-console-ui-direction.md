# ADR-0016: Console visual direction and UI rules

## Status
Accepted

## Date
2026-10-30

## Context
ADR-0006 chose Leptos for the web UI but not how the UI should look or behave. Autoplow replaces several tools with very different interfaces, and its pages are built module by module, so without shared rules they would drift apart.

Eight visual directions were mocked up with the same content: Console, Arr-native, Pipeline, Calm, Hybrid, Terminal, Panels and Triage. Console was then drawn for every screen in the module specs and refined through review.

## Decision
- **Direction:** Console. A dark, dense admin layout with a full-height sidebar, tables first, and a user-selectable accent colour.
- **Rules:** recorded in [the UI spec](../specs/ui.md):
  - tokens and the accent contrast rule
  - page versus dialog
  - unsaved-changes handling
  - row actions and width caps
  - secrets with an inline eye toggle
  - inline controls instead of separate buttons where a control can live on the thing it acts on
- **Precedence:** the UI spec is binding for every module's pages. The mockups are reference material and are kept outside the repository.

## Alternatives Considered
### Arr-native
- **Pros:** familiar to Sonarr and Radarr users.
- **Cons:** it copies another product's look, and that look is built around posters rather than the queues and tables Autoplow shows.
- **Rejected:** a poor fit for the content.

### Calm and Panels
- **Pros:** airy and approachable.
- **Cons:** much less information per screen.
- **Rejected:** admins checking queues need density.

### Pipeline, Terminal, Hybrid and Triage
- **Pros:** each solved one view well, for example flow, logs or the problem inbox.
- **Cons:** none worked across every page.
- **Kept:** their best ideas live on in Console: wait reasons on every queued item, the Health page's "needs attention first".

## Consequences
- **One reference:** module specs describe content only; layout and behaviour come from the UI spec.
- **Light theme:** none. It would need its own token set and contrast checks, so it waits for a new ADR.
- **Testing:** the UI spec's acceptance criteria are checked with Playwright and axe, so the rules are tested, not only reviewed.
