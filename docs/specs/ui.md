# Spec: web UI design rules

**Scope:** every page of the web UI, across all modules · **Decisions:** ADR-0006, ADR-0016 · **Status:** approved 2026-10-30

Module specs say *what* a page shows. This spec says *how* every page looks and behaves, so pages built by different modules feel like one app. The reference mockups are kept outside the repository; where they and this spec disagree, this spec wins.

## Principles
1. **Fewer buttons.** Every control has to earn its place.
   - Put an action where its object is: inside the field, in the row or in the section header. Don't add a separate button for it.
   - Before adding a button, check whether an existing control, an inline affordance or the dialog it opens can do the job.
   - Don't offer two ways to do the same thing on one screen.
2. **Dense, not cramped.** Admins scan a lot of rows, so tables are compact and nothing is padded for decoration. Every interactive control still has a target of at least 44 × 44 px.
3. **State is visible.** Every waiting, held or failed item shows *why*, in words, where it appears.
4. **Status never relies on colour alone.** It always pairs a colour with a symbol and words: ✓ healthy, ▲ backing off, ○ disabled.

## Look
- **Theme:** dark only.
- **Fonts:**
  - Inter for text.
  - JetBrains Mono for paths, IDs, event types, numbers and times.
- **Colour tokens:**

  | Token | Value | Use |
  |---|---|---|
  | `bg` | `#0E1014` | Page background, input background |
  | `nav` | `#12151B` | Sidebar, group headers |
  | `surface` | `#161A21` | Cards, sections, dialogs |
  | `selected` | `#1C212B` | Current nav item, selected rows, alert dialogs |
  | `border` | `#232833` | Dividers, card borders |
  | `border-strong` | `#2C3240` | Inputs, buttons |
  | `text` | `#E7E9EE` | Primary text |
  | `text-2` | `#C4CAD6` | Secondary text |
  | `muted` | `#9BA3B4` | Labels, hints, timestamps |
  | `warn` | `#F2C77F` (border `#4A3A1C`) | Problems, destructive actions |
  | `ok` | `#8FDCC8` | Healthy, done |
  | `link` | `#7CC0FF` | Links |
  | `accent` | user choice, default `#F2A93B` | See below |

- **Accent:**
  - The user picks it under Settings › Appearance, from the presets `#F2A93B`, `#3FC1A8`, `#7CC0FF` and `#E58FB6` or a custom colour.
  - A custom colour needs at least 4.5:1 contrast against `bg`; otherwise the previous colour is kept and the reason is shown.
  - Text on accent buttons is chosen automatically, dark or light, whichever contrasts more.
  - The accent is used for primary buttons, progress, focus, checkboxes and the current tab.
  - The accent is never used for status, and never for the current navigation item, which uses `selected`.
- **Density:**
  - Comfortable or compact, saved per browser.
  - Compact tightens table rows and the menu only; controls keep their 44 px.

## Layout
- **Sidebar:**
  - Runs the full height of the window and is sticky.
  - Order: Dashboard, Scans, Uploads, Throttle, Library parity, Track preferences, Notifications, then a divider, then Triggers, Targets and Settings.
  - On phones it becomes a top bar.
- **Width:**
  - List pages (Triggers, Targets, Notifications) and Settings cap their content at 1040 px, so a few columns don't spread across a wide screen.
  - Data-heavy pages (Dashboard, Health, Scans, Uploads, Throttle, Library parity, the Google Drive trigger) use the full width.
- **Settings:** the section menu has a fixed width of 200 px, and the section content sits beside it.
- **Small screens:**
  - No page scrolls sideways.
  - Wide tables scroll inside their own container.

## Pages and dialogs
- **Full pages:** report and work screens.
  - Dashboard and Health.
  - Scans, Uploads, Throttle.
  - Library parity and its finding detail.
  - Track preferences, Notifications.
  - The Google Drive trigger page.
  - The Triggers and Targets lists, and every Settings section.
- **Dialogs:** a single item from a list, opened from that list.
  - A trigger, a target or a notification channel.
  - An API key, an OAuth client or a Google account.
  - A user override.
  - Adding something with several steps (such as an Arr instance) is a stepped dialog.
- **Dialog behaviour:**
  - **Save:** disabled until something changes. While there are unsaved edits, the footer says "Unsaved changes".
  - **Closing:** Close, Cancel, Esc and a click outside all go through the same check. With unsaved edits they ask "Discard unsaved changes?", offering Keep editing or Discard.
  - **No nesting:** a dialog never opens another dialog. Pickers (folders, Drive folders) open inside the dialog.
  - **Destructive actions:** Delete and Revoke sit at the left of the footer, in the warning colour, and ask for confirmation.

## Controls
- **Rows:**
  - A row is opened with a button in its last column, not by making its name a link.
  - Row actions sit in that last column, right-aligned on one line. A row has at most two: its main action and Open. Everything else lives in the dialog or detail page.
- **Links:** only for going to another page. A link in a row's action column is styled like a button.
- **Bulk actions:** appear in the section header and act on the selected or filtered rows (for example "Apply suggested fix (2)" or "Discard all shown…").
- **Labels:** a label ending in "…" asks for confirmation before acting.
- **Fixed size:** a control whose label or icon changes keeps the same size in every state.
- **Icon-only controls:** have an accessible name, a tooltip and a 44 px target.
- **Secrets** (see the core spec, "Secrets are visible to the admin"):
  - A stored secret is masked in its dialog, with an eye toggle inside the field, like a password box. There is no separate Reveal button.
  - Lists never show secrets.
  - Copy appears only where the value is meant to be pasted elsewhere: an API key, the OAuth redirect URI.
- **Identifiers** (client IDs, IDs, paths) are never shortened in a way that hides what the admin needs to compare.

## Accessibility
- WCAG 2.1 AA.
- Every page passes axe with zero serious or critical violations (core AC9).
- Everything works with the keyboard.
- Dialogs use `aria-modal`, move focus into the dialog and return it when they close.
- A confirmation is an `alertdialog`.

## Acceptance criteria
1. Every page uses only the colour tokens above; status colours are the same for every accent.
2. Changing the accent to a colour below 4.5:1 against `bg` is refused with the measured ratio shown; button text on the accent picks the higher-contrast of dark and light.
3. In every dialog, Save is disabled until an edit, and Close, Cancel, Esc and a click outside with unsaved edits all show the discard confirmation.
4. No dialog opens another dialog (Playwright walks every dialog's controls).
5. Row actions on every table are in the last column, right-aligned, at most two per row.
6. Every interactive control measures at least 44 × 44 px, and controls with changing labels keep their size (Playwright measures both).
7. At 2560 px, list and Settings pages keep their content at 1040 px or less; at 390 px no page scrolls sideways.
8. Every page passes axe with zero serious or critical violations.
