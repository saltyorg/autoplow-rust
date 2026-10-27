# Constraints

Last reviewed: 2026-10-27 by saltydk

This file is the project's quality bar. Every row names the command that produces the verdict. **Every failure blocks**, both at task end and in CI. There is no time budget for task-end checks: the full set runs before an agent hands work back. Tightening a rule needs no ceremony. **Loosening one needs an ADR and is reported by `scripts/floor-guard.mjs`.** Lint and CI detail lives in [docs/quality-policy.md](docs/quality-policy.md).

## Floor (always enforced)
- No new suppressions: `#[allow(...)]`, `#[expect(...)]` without an Exceptions row, `coverage(off)`, `mutants::skip`, `gitleaks:allow`, `--cap-lints`.
- No unfinished work: `todo!()`, `unimplemented!()`, `TODO`/`FIXME`/`XXX`, empty `Err(_) => {}` arms.
- No easier tests: `#[ignore]`, Playwright `skip`/`fixme`/`only`, deleted test files, or assertions removed from tests that stay.
- No secrets in source, and no environment-specific details in the repository ([ADR-0015](docs/decisions/0015-public-documentation-rules.md)).
- Gate configuration (`clippy.toml`, `rust-toolchain.toml`, `deny.toml`, workflows, check scripts, the quality policy) and this file are never weakened to make a change pass.

**Checked by:** `node scripts/floor-guard.mjs --base <ref>` (exit 0 clean, 1 violation, 2 could not run) and `scripts/check-public-docs.sh`.

**Changing a gate file:** the guard can't tell tightening from loosening there, so any removed line is a finding. A commit in the range that carries a `Gate-Change: <reason>` trailer acknowledges it. The finding is still printed, but it no longer blocks, so every change to the bar has a reason on record.

## Enforced with numbers
| Dimension | Rule | Checked by | Runs at | Why this number |
|---|---|---|---|---|
| Lints | Zero findings under the workspace policy | `cargo clippy --workspace --all-targets --all-features -- -D warnings` | every edit, task end, CI | The policy already denies everything; any finding is a defect |
| Format | No diff | `cargo fmt --all --check` | every edit, task end, CI | No style debates |
| Tests | All pass | `cargo nextest run --workspace` | task end, CI | |
| Coverage | **Changed lines ≥ 90 %** | `cargo llvm-cov nextest --lcov --output-path lcov.info` then `diff-cover lcov.info --compare-branch=<base> --fail-under=90` | task end, CI | New codebase, so the bar can start strict. 90 % forces a test for nearly every line but leaves room for unreachable error plumbing |
| Assertion quality | **Mutation score ≥ 80 % on changed code** (caught ÷ (caught + missed)) | `cargo mutants --in-diff <diff> --output mutants.out` then `scripts/check-mutants.sh mutants.out 80` | task end, CI | AI-written tests often pass whether or not the code is right. 80 % is a "mature suite" level, reachable when tests are written alongside the code |
| Security: dependencies | **Zero** RustSec advisories, plus license, ban and source policy | `cargo deny check advisories bans licenses sources` | task end, CI | External opinion (the RustSec database). A daemon that holds media-server and cloud credentials shouldn't ship any known advisory |
| Security: secrets | Zero findings | `gitleaks detect --redact --no-banner` | task end, CI | External opinion. `--redact` keeps matched values out of logs and transcripts |
| Unused dependencies | None | `cargo machete` | CI | Less attack surface and shorter builds |
| UI bundle | **Leptos WASM ≤ 150 KB gzip** | `trunk build --release` then `scripts/check-wasm-budget.sh 150` | task end, CI | The measured baseline for a small page was 83 KB. 150 KB leaves room for the full admin UI while catching dependency bloat |
| Accessibility | **Zero serious or critical** axe violations on every UI page | Playwright with `@axe-core/playwright` (tags `wcag2a`, `wcag2aa`, `wcag21aa`) against the locally served UI | task end, CI | External opinion (WCAG). Moderate and minor findings are reviewed, not blocked |
| Public docs | No environment details; no broken relative links | `scripts/check-public-docs.sh`, `scripts/check-links.sh` | every commit, CI | [ADR-0015](docs/decisions/0015-public-documentation-rules.md) |
| Commit messages | Conventional Commits | `scripts/check-commit-messages.sh` | CI | Releases and the changelog are generated from them (release-please) |

**Tool availability:**
- **Available now:** the floor guard, the public-docs, link and commit-message checks, and the docs CI.
- **Installed and wired with Task 0.1:** the Rust and UI tools (cargo-nextest, cargo-llvm-cov, diff-cover, cargo-mutants, cargo-deny, cargo-machete, gitleaks, trunk, Playwright with axe), together with `scripts/check-mutants.sh` and `scripts/check-wasm-budget.sh`. Until then there is no Rust code for them to judge.

## Measured, not yet enforced
| Metric | Today | Direction |
|---|---|---|
| Project-wide line coverage | n/a (no code yet) | Recorded at the end of Task 0.1, then must not fall (0.5 % tolerance) |

## Exceptions
Every exception needs an owner and an expiry, at most 90 days out. Each `#[expect(lint, reason = "...")]` in code needs a row here.

| ID | Rule | Path | Reason | Owner | Expires |
|---|---|---|---|---|---|
