# Spec: web UI design rules

**Scope:** every page of the web UI, across all modules · **Decisions:** ADR-0006, ADR-0016 · **Status:** approved 2026-10-30

Module specs say *what* a page shows. This spec says *how* every page looks and behaves, so pages built by different modules feel like one app. The reference mockups are kept outside the repository; where they and this spec disagree, this spec wins.

## Non-goals
- A light theme
- Translations; the UI is in English
- Keyboard shortcuts beyond what the controls themselves give
- A search across the whole app

## Principles
1. **Inline before separate.** When a control can live inside or on the thing it acts on, put it there instead of adding a separate button. For example, the show/hide toggle for a secret is an eye icon inside the field. This is not a limit on buttons in general: an action the admin needs gets its button.
2. **Dense, not cramped.** Admins scan a lot of rows, so tables are compact and nothing is padded for decoration. Every interactive control still has a target of at least 44 × 44 px.
3. **State is visible.** Every waiting, held or failed item shows *why*, in words, where it appears.
4. **Status never relies on colour alone.** It always pairs a colour with a symbol and words: ✓ healthy, ▲ backing off, ✕ unavailable, ○ disabled.

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
- **Settings:**
  - Sections, in order: General, Anchors, rclone, Uploads, Downloaders, Library parity, Google Drive, API keys, Appearance, About.
  - The section menu has a fixed width of 200 px, and the section content sits beside it.
  - **Settings save as you change them.** Each card shows when it was last saved; there is no Save button. A change that needs confirming (a password) goes through a dialog, which keeps its own Save.
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
  - Sign-in.
  - The Triggers and Targets lists, and every Settings section.
- **Dialogs:** a single item from a list, opened from that list.
  - A trigger, a target or a notification channel.
  - An API key, an OAuth client or a Google account.
  - A track-preferences user, an anchor, a destination, a downloader.
  - Scanning a folder by hand, with a preview per target.
  - Adding something with several steps (such as an Arr instance) is a stepped dialog.
- **Dialog behaviour:**
  - **Save:** disabled until something changes. While there are unsaved edits, the footer says "Unsaved changes".
  - **Closing:** Close, Cancel, Esc and a click outside all go through the same check. With unsaved edits they ask "Discard unsaved changes?", offering Keep editing or Discard.
  - **No nesting:** a dialog never opens another dialog. Pickers (folders, Drive folders) open inside the dialog.
  - **Destructive actions:** Delete and Revoke sit at the left of the footer, in the warning colour, and ask for confirmation.
  - **Delete refused:** when something still uses the item, the dialog lists what does, each linking to it, and deletes nothing.
  - **Changed elsewhere:** when a save is refused because the item changed since the dialog opened, the dialog says so and offers Reload. It never overwrites silently.
- **Long jobs** (a snapshot rebuild, a full parity check, a backup): the button starts the job and the page shows it running with progress, then its result. It keeps running if the page is closed, and the button is disabled while it runs.

## Page inventory
Every page and dialog in v1, the module that owns it, what it shows and does, and the task that builds it. A module spec defines the behaviour behind a page; this table defines what is on it. *(Added 2026-11-10.)*

| Page or dialog | Module | Shows and does | Task |
|---|---|---|---|
| **Sign in** | core | Username and password; the remaining tries and the wait after too many. | 0.9 |
| **Setup** (first start only) | core | Shown while no admin exists: choose a username and password; asks for the setup token unless opened on the host itself. | 0.9 |
| **Dashboard** | core | Tiles: scans delivered and queued, upload speed and volume, parity findings. Target states with a link to Health. The next scans with their wait reasons, running uploads, and the newest parity findings, each linking to its page. Scan button. | 12.1 |
| **Health** | core | Needs attention first, each row linking to where it is fixed. Every background component with state, restarts and detail. Connections: targets, Arrs, rclone remotes, Google accounts, download clients. Recent health events. A newer release when one exists. | 0.10 |
| **Scans** | scan | The queue per target with each entry's wait reason and time, filters by target and reason, Send or Retry per entry. Dead letters with Edit (opens the path mapping), Retry, Discard and Discard all. Unmatched folders with their trigger. Delivered scans on request. | 4.4 |
| Scan (dialog) | scan | A folder with a picker; a live preview per target of the rewritten path, the library and whether the folder exists; "send now". | 4.4 |
| **Uploads** | upload | Speed, volume, readiness checks, rclone state. Running transfers with Stop; Hold and Stop all. Files not ready yet with the reason and when they become eligible. Failed files with Retry and Discard. Finished uploads on request. Destinations with remote health. | 8.6 |
| Destination (dialog) | upload | Name, local folder, exclude patterns, ordered remotes with sub-path and per-remote cap, readiness rules with the scan wait, hardlink policy, move or copy, removing empty folders. | 8.6 |
| **Throttle** | throttle | Active streams; a manual override with its time left; every limiter with direction, mode, limit now, limit with no streams, and state; sessions with what counts and which server counts are assumed; counting options: which kinds of playback count, the settling time, and no new uploads above a number of streams. | 9.4 |
| Limiter (dialog) | throttle | On or off, mode, and that mode's table or values. By-bitrate for rclone only. Says that Autoplow owns a client's limit. | 9.4 |
| **Library parity** | parity | Findings table with type, title, server, Arr, what differs, suggested fix; filters including ignored and recently fixed; bulk fix, skip and ignore; Check. | 10.3 |
| **Parity finding** | parity | Both sides compared, how the items were joined, exactly what the fix does, history; fix, skip, ignore; previous and next. | 10.3 |
| **Track preferences** | track-preferences | Users with what is remembered and when it was last applied; one user's remembered choices with Edit and Clear; recent changes; where it applies (Plex targets, libraries, excluded shows, the ignore label); when to apply and the default scope; Sweep. | 11.3 |
| User (dialog) | track-preferences | Included or opted out, scope override, Clear all. | 11.3 |
| **Notifications** | notifications | Channels with state; which events go where; undelivered messages with Resend, Discard and Discard all per channel; delivery options (the problem delay, attempts, the grouping window). | 1.2 |
| Channel (dialog) | notifications | Enabled, name, URL, events grouped by category with All and None, one optional filter for the channel, Test; shows when the channel is failing and why. | 1.2 |
| **Triggers** | scan | Every trigger with type, auth, minimum age, events today, last event, connection state. | 4.9 |
| Trigger (dialog) | scan, arr | Name, authentication (its own or the shared credentials), minimum age, extra wait per event type and filters, whether the folder must exist, targets never fed, path mappings inline. For an Arr: its URL and API key with Test, the certificate check and timeouts, a callback address of its own, Reconcile, Unmanage, the managed connection's state, and older webhooks with Disable and Delete. | 4.9 |
| Add trigger (dialog) | scan | Choose Arr, webhook, local folders or Google Drive, then that type's fields. | 4.9 |
| Add Arr instance (dialog, steps) | arr | Connect and detect; map root folders by suggestion or picker; preview of the managed connection; review. | 4.9 |
| **Google Drive trigger** | gdrive | State, Poll, Pause; settings summary; changes with outcome and filters; snapshot browser with Rebuild. | 6.4 |
| Drive trigger settings (dialog) | gdrive | Account, drive, the folders to follow (or the whole drive), crypt remote, path mapping with pickers, polling, minimum age, filters, targets never fed. | 6.4 |
| **Targets** | targets, scan | Every target with server, libraries, path mappings, queued, state. | 4.9 |
| Target (dialog) | targets, scan | Enabled, and whether scans wait or are dropped while it is off; connection with Test, Sign in with Plex, the certificate check and timeouts; pacing, maximum wait and merging of many folders into their parent; filters; whether library-root scans are allowed, whether the folder must exist and for how long to wait, and the check after delivery; how streams are read (live or by polling); path mappings with picker and "try a path"; anchors, and for Plex empty trash and merged-item handling. | 4.9 |
| Add target (dialog) | targets | Choose the server type; name, URL, token or Sign in with Plex; Test. | 4.9 |
| **Settings › General** | core | Callback base URL and Autoplow's browser address; the update check switch; admin username, Change password (dialog), the sign-in switch with its warning, trusted proxies; shared trigger credentials; time zone; scan defaults (minimum age, maximum wait, dead-letter attempts); the Arr reconcile interval; how long things are kept; backups with Backup now; log levels per component; bootstrap status. | 0.10 |
| **Settings › Anchors** | scan | Anchor files with what they hold and their state; dialog with the file picker, the targets, and an optional folder it is limited to. | 4.6 |
| **Settings › rclone** | rclone | Config path, with Reload and a note when a restart is pending; which rclone (the host's by default, or a given path); extra options and environment variables; version against the minimum; running state, or "not needed" when nothing uses it; remotes, read-only, with who uses them and their health. | 5.2 |
| **Settings › Uploads** | upload | Global transfer cap, upload windows, fixing file dates, retry attempts, cooldown times. | 8.6 |
| **Settings › Downloaders** | downloaders | Clients with what pauses and limits them and their state; dialog with Enabled, URL, credentials, Test, and pause conditions with the folder whose free space is watched. | 7.3 |
| **Settings › Library parity** | parity | When to check; automatic fixes per server and finding type, with the safety limit; match language; what is compared, with finding types and pairs that can be switched off; how long resolved findings and the fix history are kept. | 10.3 |
| **Settings › Google Drive** | gdrive | Redirect URI with its reachability check; OAuth clients and accounts, each with a dialog; setup guide. | 6.1 |
| **Settings › API keys** | core | Keys with access level and Copy; dialog to rename, change access, show, regenerate, revoke; what each access level can do. | 0.10 |
| **Settings › Appearance** | core | Accent with the contrast check and a preview; density. | 0.10 |
| **Settings › About** | core | Versions, with a newer release when one exists; licence, source, API document. | 0.10 |

## Controls
- **Rows:**
  - A row is opened with a button in its last column, not by making its name a link.
  - Row actions sit in that last column, right-aligned on one line.
  - Buttons in the same column have the same width: a lone action button fills the column, which is as wide as its widest button.
- **Button labels are one word** whenever one word says clearly what happens: Send, Retry, Edit, Discard, Open, Copy, Test, Add, Delete.
  - The page, section or row gives the rest. The full meaning goes in the button's accessible name, for example "Edit path mapping for OK Computer".
  - A second word is added only when one word would be ambiguous: two "Choose" buttons side by side, or "Stop all…" next to per-row "Stop".
  - Links and navigation are named after where they go and are not limited to one word.
- **Links:** only for going to another page. A link in a row's action column is styled like a button.
- **Bulk actions:** appear in the section header and act on the selected or filtered rows (for example "Fix (2)" or "Discard all…").
- **Labels:** a label ending in "…" asks for confirmation before acting.
- **Fixed size:** a control whose label or icon changes keeps the same size in every state.
- **Icon-only controls:** have an accessible name, a tooltip and a 44 px target.
- **Secrets** (see the core spec, "Secrets are visible to the admin"):
  - A stored secret is masked in its dialog, with an eye toggle inside the field, like a password box. There is no separate Reveal button.
  - Lists never show secrets.
  - Copy appears only where the value is meant to be pasted elsewhere: an API key, the OAuth redirect URI.
- **Identifiers** (client IDs, IDs, paths) are never shortened in a way that hides what the admin needs to compare.

## Behaviour
- **Loading, empty and failed:**
  - While a page loads, its sections show placeholders in their final shape.
  - An empty list says what belongs there and how to add it.
  - A load that fails shows the reason in words, with Retry. A page never shows a blank area.
- **Results of actions** *(decided 2026-11-10)*:
  - The row, card or dialog an action was started from shows its result and any error, in words, next to the control.
  - When the row itself is removed (a delete, a discard), a status line at the top of its section says what happened.
  - There are no pop-up messages elsewhere on the screen.
- **Long lists** *(decided 2026-11-10)*: the first 100 rows, then a More button that adds the next 100. Filters and position are kept, and the number shown is stated.
- **Live updates:**
  - Values change in place. Rows are not reordered, and the row under the pointer or the keyboard focus does not move.
  - New rows that would push others down are announced by a "New" line at the top of the list, which adds them when pressed.
  - **Connection lost:** a banner says live updates have stopped. When they return, the page reloads its data and the banner goes.
- **Addresses:** every page, open dialog and filter has its own address. Reloading returns to the same view, Back closes a dialog, and links in notifications open the item they name.
- **Session ended:** the sign-in page appears and then returns the admin to where they were.
- **Settings that fail to save:** the card says why and does not show Saved. A setting changed elsewhere since the page loaded offers Reload.
- **Form errors:** shown at the field, in words, when the field is left and on Save.
- **Times:** in Autoplow's time zone, 24-hour. Times in the last day are relative ("3 min ago"), with the exact time on hover and focus.
- **Motion:** when the system asks for reduced motion, nothing animates beyond a fade.
- **Browsers:** the two latest versions of Chrome, Firefox and Safari.

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
5. Row actions on every table are in the last column, right-aligned on one line, and lone buttons in a column all have the same width.
6. Every interactive control measures at least 44 × 44 px, and controls with changing labels keep their size (Playwright measures both).
7. At 2560 px, list and Settings pages keep their content at 1040 px or less; at 390 px no page scrolls sideways.
8. Every page passes axe with zero serious or critical violations.
9. Every button label is one word unless a second word is needed to tell it apart from a nearby button, and every button has an accessible name that says what it acts on.
10. Every page and dialog in the page inventory exists, is reachable from the sidebar or the page that owns it, and shows what its row lists (one Playwright walk per row).
11. A list with nothing in it says what belongs there and how to add it; a load that fails shows the reason and Retry. No page shows a blank area.
12. The result of an action, and any error, appears on the row, card or dialog it was started from; when the row is removed, a status line at the top of its section says what happened. No message pops up elsewhere.
13. A long list shows 100 rows and a More button that adds the next 100, keeping filters and position, with the number shown.
14. When live updates stop, a banner says so; when they return, the page reloads its data and the banner goes. A live update never reorders rows or moves the row under the pointer or the keyboard focus.
15. Every page, open dialog and filter has its own address: reloading returns to the same view, Back closes a dialog, and a notification link opens the item it names.
16. A setting that fails to save shows the reason on its card and never shows Saved; a field with an invalid value says why at the field.
17. After the session ends, the sign-in page returns the admin to the address they were on.
18. With reduced motion requested by the system, nothing animates beyond a fade.
