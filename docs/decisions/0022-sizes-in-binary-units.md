# ADR-0022: Sizes are binary units, budgets included

## Status
Accepted

## Date
2026-11-11

## Context
The specs wrote sizes as MB, GB and KB without saying whether they meant powers of 1000 or of 1024. rclone, which Autoplow drives, reads `M` as MiB, and a value sent in the wrong form is off by a factor of 1024 (see the [rclone platform note](../platform-notes/rclone.md)). The UI was changed to show speeds in MiB/s and sizes in KiB, MiB, GiB and TiB. That left Autoplow's own budgets, the limits its tests enforce, in an unstated base.

## Decision
- Every size in the specs, `CONSTRAINTS.md` and the UI is a binary unit: KiB, MiB, GiB, TiB.
- The budgets keep their numbers and change their unit:
  - idle memory ≤ 64 MiB, steady-state memory ≤ 256 MiB;
  - trigger body ≤ 1 MiB, response cap 4 MiB;
  - disk reserve 64 MiB;
  - UI bundle ≤ 150 KiB gzip.
- The scale goals change unit the same way: at least 300 TiB under management and 10 TiB uploaded per day.
- Measurements recorded earlier (for example the bundle baseline in ADR-0006) stay as they were written.

## Alternatives Considered
### Decimal budgets, stated once
- **Pros:** no limit changes.
- **Cons:** two bases in one project: a 64 MB budget beside a 64 MiB chunk, and tools that report memory in MiB compared against a decimal limit.
- **Rejected:** one base everywhere removes the question each time a number is read.

### Leave the base unstated
- **Rejected:** whoever writes each check would pick one, and the checks would disagree.

## Consequences
- Each budget is about 4.9 % larger than a decimal reading of the same number (2.4 % for the KiB one). This is a deliberate loosening, recorded here as `CONSTRAINTS.md` requires. The scale goals become about 10 % more demanding.
- Checks compare in bytes: 64 MiB is 67 108 864 bytes, 150 KiB is 153 600 bytes.
- `MB`, `GB`, `TB` and `KB` no longer appear as units in specs or the UI, apart from quoted measurements and other tools' option names.
