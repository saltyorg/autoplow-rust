# Rust quality policy (aggressive, tuned for AI-written code)

**Status:** accepted ([ADR-0005](decisions/0005-aggressive-quality-policy.md)). The exact configuration is in the appendix. In the workspace it lives in `[workspace.lints]`, and every crate sets `lints.workspace = true`.

## Why
- The Rust compiler and clippy can turn the typical failure modes of AI-written code into **build errors**:
  - panics: unwrap, indexing, string slicing
  - silently swallowed errors and dropped futures
  - locks held across `.await`
  - lossy numeric casts
  - wildcard matches that hide new enum variants
  - lints switched off without a reason
- Noise is cheap when an agent writes the code. A missed bug isn't. So we enable whole groups and deny everything, then relax only lints that are proven noisy, each with a reason.
- Lints that don't fire today still act as tripwires for future changes.

## Verified (clippy 1.99.1)
- **A clean file passes with zero findings.**
- **A file of 18 planted AI-style mistakes failed with 30 distinct lints,** catching every planted mistake plus extras such as `future_not_send` and `unused_async`.
- **One lint no longer exists:** `string_to_string` has been removed (`implicit_clone` covers it).
- **One conflict:** `clippy::redundant_pub_crate` (nursery) contradicts rustc's `unreachable_pub` in private modules. We keep `unreachable_pub` and allow `redundant_pub_crate`.
- **The `cargo` group requires package metadata** (license, description, repository, readme, keywords, categories) on every crate.

## Policy
1. **Rustc:**
   - `unsafe_code = forbid`.
   - `warnings = deny`.
   - The groups `future_incompatible`, `rust_2018_idioms`, `nonstandard_style` and `unused` are denied.
   - These individual lints are denied: `unused_must_use`, `unreachable_pub`, `missing_debug_implementations`, `unused_qualifications`, `unused_lifetimes`, `single_use_lifetimes`, `trivial_casts`, `trivial_numeric_casts`, `let_underscore_drop`, `elided_lifetimes_in_paths`, `non_ascii_idents`, `unit_bindings`, `redundant_lifetimes`, `unexpected_cfgs`.
2. **Clippy groups:** `all`, `pedantic`, `nursery` and `cargo` are **denied** at priority -1, so specific overrides take precedence.
3. **Clippy restriction picks (denied):**

   | Category | Lints |
   |---|---|
   | Never panic | `unwrap_used`, `expect_used`, `panic`, `todo`, `unimplemented`, `unreachable`, `get_unwrap`, `indexing_slicing`, `string_slice`, `unwrap_in_result`, `panic_in_result_fn`, `unchecked_time_subtraction`, `missing_asserts_for_indexing`, `exit` |
   | Never fail silently | `let_underscore_must_use`, `let_underscore_future`, `let_underscore_untyped`, `unused_result_ok`, `map_err_ignore`, `assertions_on_result_states`, `wildcard_enum_match_arm`, `match_wildcard_for_single_variants`, `try_err`, `error_impl_error` |
   | Async | `await_holding_lock`, `await_holding_refcell_ref`, `large_futures`, `mutex_atomic`, `rc_mutex`, `mem_forget` |
   | Numbers | `arithmetic_side_effects` (use `checked_*`, `saturating_*`), `as_conversions` (use `TryFrom`), every `cast_*` lint, `float_cmp`, `float_cmp_const`, `lossy_float_literal`, `integer_division`, `modulo_arithmetic`, `invalid_upcast_comparisons` |
   | Hygiene | `dbg_macro`, `print_stdout`, `print_stderr` (use `tracing`), `clone_on_ref_ptr`, `rest_pat_in_fully_bound_structs`, `tests_outside_test_module`, `partial_pub_fields`, `same_name_method`, `infinite_loop`, `iter_over_hash_type`, `debug_assert_with_mut_call`, `verbose_file_reads`, `fn_to_numeric_cast_any`, `missing_assert_message`, `undocumented_unsafe_blocks` |
   | Suppressions | `allow_attributes`, `allow_attributes_without_reason`. Every exception must be written `#[expect(lint, reason = "...")]`, so it is visible, justified, and itself fails once it is no longer needed. |

4. **Relaxed, with a reason:**
   - `module_name_repetitions` (noise).
   - `multiple_crate_versions` (transitive duplicates aren't actionable).
   - `redundant_pub_crate` (the conflict above).
5. **`clippy.toml`:**
   - Tests may use unwrap, expect, panic, indexing and dbg.
   - `too-many-lines-threshold = 80`, `cognitive-complexity-threshold = 15`, `too-many-arguments-threshold = 5`, `max-fn-params-bools = 1`.
6. **Build profile:**
   - `overflow-checks = true` in **release**, so arithmetic that slips past lints still can't wrap silently.
   - `panic = "unwind"` (not abort), so the supervisor can catch a panic in a task as a last resort and restart that component.
7. **Toolchain pinned** in `rust-toolchain.toml` (1.99.1). New clippy releases add lints, and with `-D warnings` they would otherwise break CI unexpectedly. Bump the pin deliberately.

## CI gates (beyond lints)
| Gate | Purpose |
|---|---|
| `cargo fmt --check` | Formatting |
| `cargo clippy --workspace --all-targets --all-features -- -D warnings` | The policy above |
| Check that every member crate sets `lints.workspace = true` | Stops a crate opting out silently |
| `cargo nextest run` | Tests |
| `cargo llvm-cov` with a coverage floor (start at 80% on core crates) | Untested code |
| **`cargo mutants`** on core crates (paths, queue, readiness, policy) | Catches tests that pass whether or not the code is right, which AI-written tests often do. Gate on surviving mutants in changed code |
| `cargo deny` (advisories, licenses, bans, sources) | Supply chain |
| `cargo machete` | Unused dependencies |
| `proptest` property tests | Path normalisation, rewrite rules, queue state machines |

## Coding conventions that support the lints
- **Errors:** typed `thiserror` errors in libraries, `anyhow` only in `main`. No `String` errors.
- **Domain types:** newtypes for IDs and paths, and `#[must_use]` on results and builders.
- **State machines:** exhaustive `match` on enums, with no wildcards (enforced).
- **Time:** an injected `Clock` trait for wall-clock time, and `tokio::time::pause` in tests.
- **Secrets:** wrapped in `secrecy::SecretString`, so they can't reach logs.

## Appendix: exact configuration (verified)
### `Cargo.toml` (workspace root)
```toml
[workspace.lints.rust]
unsafe_code = "forbid"
warnings = { level = "deny", priority = -2 }
future_incompatible = { level = "deny", priority = -1 }
rust_2018_idioms = { level = "deny", priority = -1 }
nonstandard_style = { level = "deny", priority = -1 }
unused = { level = "deny", priority = -1 }
unused_must_use = "deny"
unreachable_pub = "deny"
missing_debug_implementations = "deny"
unused_qualifications = "deny"
unused_lifetimes = "deny"
unused_import_braces = "deny"
single_use_lifetimes = "deny"
trivial_casts = "deny"
trivial_numeric_casts = "deny"
let_underscore_drop = "deny"
elided_lifetimes_in_paths = "deny"
non_ascii_idents = "deny"
meta_variable_misuse = "deny"
unit_bindings = "deny"
redundant_lifetimes = "deny"
missing_unsafe_on_extern = "deny"
unexpected_cfgs = "deny"

[workspace.lints.clippy]
# Whole groups, lower priority so individual overrides below win.
all = { level = "deny", priority = -1 }
pedantic = { level = "deny", priority = -1 }
nursery = { level = "deny", priority = -1 }
cargo = { level = "deny", priority = -1 }

# --- Never panic (tests exempted via clippy.toml) ---
unwrap_used = "deny"
expect_used = "deny"
panic = "deny"
todo = "deny"
unimplemented = "deny"
unreachable = "deny"
get_unwrap = "deny"
indexing_slicing = "deny"
string_slice = "deny"
unwrap_in_result = "deny"
panic_in_result_fn = "deny"
unchecked_time_subtraction = "deny"
missing_asserts_for_indexing = "deny"
exit = "deny"

# --- Never fail silently ---
let_underscore_must_use = "deny"
let_underscore_future = "deny"
let_underscore_untyped = "deny"
unused_result_ok = "deny"
map_err_ignore = "deny"
assertions_on_result_states = "deny"
wildcard_enum_match_arm = "deny"        # force exhaustive matches: new variants must be handled
match_wildcard_for_single_variants = "deny"
try_err = "deny"
error_impl_error = "deny"

# --- Async / concurrency ---
await_holding_lock = "deny"
await_holding_refcell_ref = "deny"
large_futures = "deny"
mutex_atomic = "deny"
rc_mutex = "deny"
mem_forget = "deny"

# --- Numbers: no silent wrap / truncation / lossy casts ---
arithmetic_side_effects = "deny"
as_conversions = "deny"
cast_possible_truncation = "deny"
cast_possible_wrap = "deny"
cast_precision_loss = "deny"
cast_sign_loss = "deny"
float_cmp = "deny"
float_cmp_const = "deny"
lossy_float_literal = "deny"
integer_division = "deny"
modulo_arithmetic = "deny"
invalid_upcast_comparisons = "deny"

# --- Hygiene that agents get wrong ---
dbg_macro = "deny"
print_stdout = "deny"                    # use tracing
print_stderr = "deny"
clone_on_ref_ptr = "deny"
rest_pat_in_fully_bound_structs = "deny"
tests_outside_test_module = "deny"
partial_pub_fields = "deny"
same_name_method = "deny"
infinite_loop = "deny"
iter_over_hash_type = "deny"             # HashMap order is nondeterministic
debug_assert_with_mut_call = "deny"
verbose_file_reads = "deny"
fn_to_numeric_cast_any = "deny"
missing_assert_message = "deny"
undocumented_unsafe_blocks = "deny"

# --- No silent suppression: every exception needs #[expect(.., reason = "..")] ---
allow_attributes = "deny"
allow_attributes_without_reason = "deny"

# --- Known-noisy group members we relax deliberately ---
module_name_repetitions = "allow"
multiple_crate_versions = "allow"       # transitive dep duplicates aren't actionable
redundant_pub_crate = "allow"           # conflicts with rustc unreachable_pub in private modules; we keep unreachable_pub

[profile.release]
overflow-checks = true                   # arithmetic overflow panics are caught by the supervisor, not silent wraps
debug = "line-tables-only"
```

### `clippy.toml`
```toml
allow-unwrap-in-tests = true
allow-expect-in-tests = true
allow-panic-in-tests = true
allow-indexing-slicing-in-tests = true
allow-dbg-in-tests = true
too-many-lines-threshold = 80
cognitive-complexity-threshold = 15
too-many-arguments-threshold = 5
max-fn-params-bools = 1
avoid-breaking-exported-api = false
```

### Every member crate
```toml
[lints]
workspace = true
```
