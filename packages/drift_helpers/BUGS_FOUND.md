# BUGS_FOUND — drift_helpers test hardening pass

Originally authored against `packages/tu_sync/` in the
`tupandas/ire` monorepo (worktree `worktree-agent-ac1cd97c0ea11d51c`).
Carried over verbatim during the fork-out into the standalone
`drift_helpers` package. Same observations apply: the package is a
converter-only shim with no `@DriftDatabase` of its own, no Equatable
state classes, and no BLoC — so schema-baseline / stringify / `fake_async`
work is N/A.

## #1 — Deferred: drift schema baseline / SchemaVerifier — N/A in `drift_helpers`

**Status:** Deferred (structural — not a bug).

A `drift_dev schema dump` + `SchemaVerifier` round-trip test was scoped
for the converter package, but:

- `rg '@DriftDatabase' lib/`            → 0 matches
- `rg '@DataClassName' lib/`            → 0 matches
- `rg 'class .* extends Table' lib/`    → 0 matches

`drift_helpers` is **only a converter shim** (pure-Dart). It contains
`JsonConverter`, `JsonListConverter`, `IntListConverter`,
`StringListConverter` (all `TypeConverter` subclasses in
`lib/src/converters/`) and nothing else.

**Action:**

- A DAO smoke test using a real in-memory `sqlite3` engine **is**
  applicable and was implemented — see
  `test/dao/converter_dao_smoke_test.dart`. It exercises every converter
  through real INSERT/SELECT round-trips, which is the highest-leverage
  check available inside this package.
- Re-route schema-baseline work to packages that actually own a
  `@DriftDatabase` (in the ire monorepo:
  `apps/tuSpeech/lib/core/database/database.dart` and aiNote's
  `database/database.dart`), or upstream into
  `offline_first_sync_drift`. That work cannot live here.

## #2 — Deferred: stringify codemod — N/A in `drift_helpers`

**Status:** Deferred (structural — not a bug).

`rg 'extends Equatable' lib/` → 0 matches. No state classes, no BLoC.
Nothing to codemod.

## #3 — Deferred: `clearMessage` and `fake_async` — N/A in `drift_helpers`

**Status:** Not applicable. No BLoC. No real-time waits in any test.
