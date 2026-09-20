# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.4] - 2026-09-21

### Fixed

- **One unreadable row no longer stops a kind from syncing.** `pullKind`
  called `fromJson` for every row of a page without a guard; a single row the
  model cannot read (a `null` where it needs a value, a field with another
  type) failed the page. The cursor only moves when a page was stored, so
  every later sync failed at the same place, forever. Such a row is now
  skipped and reported as a `SyncErrorEvent` carrying a `ParseException` with
  its id; the rows around it are stored and the cursor moves on. The same
  goes for a row the database rejects, for a page item that is not a JSON
  object at all (`RestTransport` hands over a lazily cast list), and for a
  row without `updated_at` or `id` at the end of a page — the cursor goes to
  the last row that names both. A full page that neither moves the cursor nor
  names a next page ends the pull instead of being requested again without
  end. `SyncConfig.skipInvalidPulledRows: false` restores the old, strict
  behaviour (useful while developing).
- **An interrupted full resync continues instead of starting over.** It reset
  all cursors first and recorded completion last, so a connection that
  dropped after page 3 of 200 meant page 1 again next time — on a flaky
  network it might never finish. The cursors a full resync reaches are kept;
  a marker cursor (`CursorKinds.fullResyncInProgress`) tells the next sync to
  carry on from them — whenever the last complete resync was, so the marker
  never outlives the work. `fullResync(clearData: true)` is still a clean
  slate.
- **A push-only sync no longer sets off the periodic full resync.** The
  full-resync check ran before the kind filters were looked at, so
  `sync(pushKinds: …, pullKinds: {})` — the debounced push after a local
  write — downloaded every table when the 7 days were up. It now waits for
  the first sync that pulls. (A database's very first sync is such a resync:
  if your first call is push-only, the initial download happens with the
  first call that pulls.)
- **An upsert the server answers with "not found" is no longer dropped
  silently.** `PushNotFound` was acknowledged like a success for every op:
  the user's edit vanished without an event or a counter. For an upsert it is
  now a rejection like any other 4xx — `OperationFailedEvent`
  (`TransportException`, 404), counted, stuck once the retry budget is used
  up. For a delete it still means "done".
- **Dropping operations no longer leaves their effect behind.**
  `dropStuckOperations()` only deleted the ops; the local row kept the edit
  that was given up, and with nothing queued it looked synced while it
  differed from the server. Every affected row is now fetched again
  (`TransportAdapter.fetch`) and written back, or removed when the server
  does not have it. An op whose row cannot be fetched right now is kept and
  reported. Rows are settled one by one (row and acknowledgement in one
  transaction), a row with newer operations still queued — also ones enqueued
  while the server was being asked — is left to them, and a server row the
  app cannot read is reported while the ops are dropped as asked. With
  `skipConflictingOps: true` the row becomes what the server reported in the
  conflict.
- **One conflict that cannot be resolved no longer fails every sync of its
  kind.** Conflicts of a batch were resolved in a loop and acknowledged
  together afterwards. Resolving can throw — the `409` carries a record
  `fromJson` cannot read, the app's `conflictResolver`/`mergeFunction` fails,
  the forced push loses the connection — and that exception skipped the
  acknowledgement of every conflict resolved before it (rows already
  rewritten, the merge already on the server, the user already asked: they
  were asked again) and failed the push, so the pull never ran either. A
  conflict was never counted as an attempt, so this repeated on every sync.
  Each conflict is now acknowledged as soon as it is resolved; one that
  throws is an `OperationFailedEvent`, counted like any other failure (not
  when it is environmental) and stuck once the budget is used up.
- **A full resync no longer sends operations a second time while a push of
  theirs is under way.** It shared its run with other full resyncs, but did
  not look at per-kind runs: with `pushOnEnqueue` the debounced push after a
  local write and the app's first `sync()` (a full resync on a new database)
  pushed the same, not yet acknowledged operations concurrently. It now waits
  for the per-kind runs that are under way; new ones join it.
- `SyncErrorEvent.phase` says where a failed run was. It was `SyncPhase.pull`
  for every failure of `sync()`/`fullResync()`, also when pushing failed.
- `dispose()` while a sync is running no longer fails that run with
  "Cannot add new events after calling close" (a `StateError`, outside the
  `SyncException` hierarchy, which also replaced the run's own error). The
  run finishes quietly. `sync()`/`fullResync()` on a disposed engine throw a
  `StateError` that says so.
- `sync()` on an engine without tables failed with "Bad state: No element"
  from the second call on.
- `startAuto()` dropped the future of every tick, so each failed one — all of
  them while the device is offline — surfaced as an unhandled asynchronous
  error (a "fatal" in most crash reporters). Failures are on `events`, where
  they always were.

### Changed

- `AcceptMerged`, `MergeInfo`, `PushNotFound`, `PushError` and
  `BatchPushResult` are declared with const primary constructors and are now
  `final`: they can no longer be extended or implemented outside the package
  (constructing and matching them is unchanged).
- Internal: `SyncEngine` is written with a primary constructor and lost about
  a third of its length — stuck-operation handling, the debounced
  push-on-enqueue and the run-reporting scaffold moved into their own
  classes, `SyncRunResult`/`PullStats` into `src/sync_run_result.dart` (still
  exported from the package). No API or behaviour change.

## [0.2.3] - 2026-09-20

### Fixed

- A queued **delete** that conflicts with an edit made elsewhere is resolved
  under `ConflictStrategy.autoPreserve` — the default — and `merge`: the
  server's version is kept (written back locally) and the delete is dropped.
  Both strategies answered `AcceptMerged`, which cannot be pushed for a
  delete, so the op was reported unresolved, never counted as an attempt,
  never became stuck, and was sent again by every sync, forever. A manual
  resolver that returns `AcceptMerged` for a delete gets the same treatment.
  `clientWins` / `lastWriteWins` still delete, `serverWins` still keeps.
- Stream queries on the sync tables are re-run when the library changes them.
  `ackOutbox`, `incrementOutboxTryCount`, `resetOutboxTryCount`,
  `deleteOutboxMeta`, `purgeOutboxOlderThan`, `resetAllCursors` and
  `clearSyncableTables` ran raw SQL without telling drift which table they
  touched, so after a successful sync `watchOutboxCount()` /
  `OutboxService.watchPendingCount()` / `watchStuckOutboxCount()` — and any
  `watch()` an app builds on `sync_outbox`, e.g. a per-item "synced / not sent
  yet" label — kept their old value until the app restarted. After
  `fullResync(clearData: true)` lists kept showing the wiped rows when the
  pull brought nothing.

## [0.2.2] - 2026-09-19

### Fixed

- **Being offline no longer parks the outbox.** `maxOutboxTryCount` (default
  5) counted every failed push, including "no network". After five sync
  attempts without a connection — 25 minutes with `startAuto()`'s default
  interval — every queued write was "stuck": `take()` skipped it from then on
  and it was never sent, not even once the connection was back, unless the app
  called `retryStuckOperations()`. An expired token (`401`) or a server outage
  (`5xx`) did the same. The budget is now only used up by failures that are
  about the operation: see "Changed".
  **Upgrade note:** operations parked by the old behaviour stay parked. If
  your app may have users in that state, call `engine.retryStuckOperations()`
  once after upgrading.
- The pull cursor keeps the microseconds of the server version
  (`sync_cursors.ts`; no schema change, cursors written by older versions are
  still read). Truncated to milliseconds it pointed just before the last row
  of a server with microsecond versions, so every later pull downloaded that
  row — and everything else within the same millisecond — again.
- Timestamps between 1966 and 1973 survive the outbox and the cursor table:
  their microsecond value is below the threshold that tells microseconds from
  the milliseconds older versions wrote, so e.g. a base version of
  `1970-01-01T00:00:05Z` (a legacy row whose `updated_at` was defaulted) came
  back as `01:23:20`. Such values are now stored as milliseconds.

### Changed

- A failed push only counts against an operation's retry budget when the
  failure is about the operation: a `4xx` other than `401`, `403`, `408`,
  `425`, `429`, or an error without a status. No network, timeouts, `401` /
  `403`, `408` / `425` / `429` and any `5xx` leave `try_count` alone. They are
  still reported — `OperationFailedEvent` (now with `willRetry: true`),
  `SyncStats.errors`, `last_error` / `last_tried_at` in `sync_outbox_meta`.
- `SyncErrorInfo.fromError` classifies a bare `TimeoutException` as `network`,
  and `408` / `425` / `429` as `retryable`.

### Added

- `SyncErrorInfo.isEnvironmental`: whether a failure describes the conditions
  an operation was sent under rather than the operation.
- `recordOutboxFailures(..., countAttempts: false)` /
  `OutboxService.recordFailures(..., countAttempts: false)`: store the last
  error without counting an attempt.

## [0.2.1] - 2026-09-19

### Added

- Indexes on `sync_outbox`: `(kind, ts)`, `(ts)` and `(kind, entity_id)`.
  The engine reads the queue once per batch and updates it once per pushed
  op; without an index each of those statements scanned — and sorted — the
  whole queue, so draining N ops cost N². With 20 000 queued ops, taking a
  batch drops from 9.4 ms to 0.09 ms and re-basing an entity from 6.3 ms to
  0.16 ms (native SQLite).
  **What you need to do:** re-run `build_runner`, so your generated database
  lists the indexes and new installations create them. Databases that already
  exist need no migration: `SyncEngine` creates the indexes before its first
  sync. They are declared `IF NOT EXISTS`, so a `Migrator.createIndex` for
  them in your own migration is harmless too. If you verify your schema after
  migrations (`validateDatabaseSchema`), call the new
  `SyncDatabaseMixin.ensureSyncIndexes()` in `onUpgrade`.
- `SyncDatabaseMixin.ensureSyncIndexes()`: creates the outbox indexes on a
  database that does not have them; safe to call at any time.
- `SyncDatabaseMixin.rebaseQueuedOutboxOps` / `OutboxService.rebaseAll`:
  `rebaseOutboxOps` for many entities at once; only the ones that still have
  ops queued are touched.
- `parseServerTimestamp` is public: how the engine reads a server timestamp
  (a value without a zone designator is UTC), for transports to use.

### Changed

- `PushService` applies a pushed batch to the local database in **one
  transaction**: the rows the server returned, the acknowledgement, the
  failure counters and the re-base of what is still queued. It used to be one
  implicit transaction per statement (52 commits for a batch of 25), and a
  crash in between left rows written back whose ops were still queued.
  `OperationPushedEvent`, `OperationFailedEvent` and `PushBatchProcessedEvent`
  are emitted after that transaction, so a listener sees the outbox and the
  local rows as the event describes them. After a batch only the entities
  that still have ops queued are re-based (one lookup instead of one `UPDATE`
  per pushed op).
- `recordOutboxFailures` writes the metadata of all failed ops in one batched
  statement.
- `SyncEntityWriter.replaceAndEnqueueDiff` calls your `toJson` once per
  entity (it serialized the new entity twice), and payloads are no longer
  wrapped in a `CastMap`.
- On the web the push no longer reads the local row of every op: it was
  looking for sub-millisecond digits a browser `DateTime` cannot hold.

### Fixed

- A pull no longer ends at an empty page that names a next page. Servers that
  filter after paginating (row-level permissions, a DynamoDB
  `FilterExpression`) return such pages; the rows behind them were never
  downloaded, and since the cursor did not move every later sync stopped at
  the same place. The token is followed; a token that repeats, or more than
  32 empty pages in a row, ends the pull.
- A transport that returns no result for an op it was given no longer keeps
  `pushAll` pushing that op in a loop: the op counts as failed
  (`TransportException`, `tryCount` + 1) and the push ends. A result for an
  op that was not part of the batch still throws, now naming the op id.

## [0.2.0] - 2026-09-19

### Breaking

- The minimum Dart SDK is now **3.13** (was 3.7).
- `ConflictUtils.preservingMerge` — and therefore the default
  `ConflictStrategy.autoPreserve` — now treats a field that is listed in
  `changedFields` and is `null` locally as a deliberate clear: the merged
  result contains `null`. It used to keep the server's old value, silently
  undoing the user's edit. Without `changedFields` the server value is still
  preserved.

### Added

- `SyncDatabaseMixin.rebaseOutboxOps` / `OutboxService.rebase`: re-base the
  queued ops of one entity onto a version the server reported.
- `ConflictResolutionResult.serverData`: the entity as the server holds it
  after a resolved conflict.
- Add opt-in `pushOnEnqueue` config (default `false`). When enabled, every
  outbox enqueue schedules a debounced per-kind auto-push (debounce window
  configurable via `enqueuePushDebounce`, default 250ms). Combines with the
  per-kind sync locks: rapid writes for one kind coalesce into a single
  push; different kinds push in parallel. Useful for apps that want
  low-latency reads on the server side without polling.

### Changed

- Per-kind sync locks: concurrent `sync()` calls with disjoint `pullKinds`/`pushKinds`
  now run in parallel; same-kind concurrent calls coalesce as before. Full-resync
  gating unchanged — a full resync still serialises all concurrent callers onto a
  single `_fullResyncFuture`.
- All-final classes (ops, sync events, services, `PullPage`, …) are annotated
  `@immutable` and have `const` constructors. Adds a dependency on `meta`.
- Constructors use private named parameters (`this._db`); call sites keep the
  public names (`db:`), so nothing changes for callers.
- Dependencies: `drift` ^2.35.0.

### Changed — how the base version of an op is determined

- The `baseUpdatedAt` you pass to `replaceAndEnqueue` & co. is authoritative
  again. Since 0.1.x the engine replaced it, right before dispatch, with the
  local row's `updated_at`. That column belongs to the app: stamping it with
  "now" on edit — as most apps and this repo's examples do — made **every**
  edit a conflict, and after a pull had stored another client's write there a
  real conflict was silently swallowed (the queued edit overwrote it). Pass
  the `updatedAt` of the entity as it was **before** the edit.
- The stale-base problem that replacement was solving is now fixed where the
  version is learned: after a successful push (or a resolved conflict) the
  `updated_at` of the row the server returned is written into the base of
  the entity's remaining queued ops. Servers must return the saved record for
  this to work.
- Ops of one entity are pushed one per batch, oldest first, and never past
  one that failed. Two quick edits no longer need `pageSize: 1` to avoid a
  stale-base conflict, and a transport with `pushConcurrency > 1` can no
  longer race ops of the same entity.
- After a conflict is resolved by a force push, the row the server returned
  is written to the local table (it used to be the merged data, which still
  carried the version it replaced, so the next edit conflicted again).
- `sync_outbox.base_updated_at` stores **microseconds** (it truncated to
  milliseconds, which never equals a microsecond `updated_at`). No schema
  change: rows written by older versions are still read correctly.
- Upgrade note: ops already queued with a base that went stale under the old
  behaviour may be reported as a conflict once; your strategy resolves it.

### Fixed

- Every edit of a synced entity was rejected as a conflict when the app
  stamps `updatedAt` on edit (see "Changed" above).
- Outbox ops enqueued within the same millisecond are returned in insertion
  order (`ORDER BY ts, rowid`); ties used to be unordered.
- `PushService.pushAll` no longer spins forever when a conflict stays
  unresolved (e.g. `ConflictStrategy.manual` with `DeferResolution`, or a
  `forcePush` that keeps conflicting). The operation was neither acked nor
  counted as a failure, so the push loop re-took and re-pushed it without end:
  `sync()` never returned and the server was hit continuously. The loop now
  stops after such a batch and the operation is retried by the next sync.
- List merge no longer duplicates items that have no `id`: equal, separately
  decoded maps were compared by identity and appended again on every conflict
  (a one-item list grew to 2, 4, 8, 16 …).
- The pull cursor reads a server timestamp without a zone designator
  (`2024-01-01T10:00:00`) as UTC. It was parsed as device-local time; west of
  UTC the cursor jumped ahead and rows in the gap were skipped until the next
  full resync.
- A pulled item without any id (`id` / `ID` / `uuid`) now throws
  `ParseException` instead of persisting the cursor id `"null"`.

## [0.1.2] - 2026-02-13

### Added

- DX sugar for outbox ops:
  - `UpsertOp.create(...)` and `DeleteOp.create(...)` auto-generate `opId` and UTC timestamps
- High-level write helpers:
  - `SyncWriter` and typed `SyncEntityWriter<T>` for atomic "local write + enqueue"
  - `SyncDatabaseDx` extension one-liners (`insertAndEnqueue`, `replaceAndEnqueue`, `enqueueDelete`, `writeAndEnqueueDelete`)
- `ChangedFieldsTracker` helper to reduce mistakes with `changedFields`
- `SyncRepository` base class for common CRUD patterns

### Changed

- `SyncableTable<T>` can derive `id` / `updatedAt` via `toJson` fallback (recommended to still pass `getId` / `getUpdatedAt`)

## [0.1.1] - 2025-01-27

### Fixed

- Fixed modular generation compatibility for Drift databases
- Improved code examples in documentation

### Documentation

- Updated README with complete model examples including `@JsonSerializable`
- Fixed import statements for modular generation (`import` instead of `part`)
- Added missing dependencies (`json_annotation`, `json_serializable`) to installation guide
- Improved conflict resolution examples with proper `switch` expression

## [0.1.0] - 2024-11-27

### Added

- Initial release
- `SyncEngine` for push/pull synchronization with conflict resolution
- `SyncDatabaseMixin` for Drift database integration
- `SyncColumns` mixin for syncable tables (adds `updatedAt`, `deletedAt`, `deletedAtLocal`)
- `SyncableTable<T>` registration for entities
- Conflict resolution strategies:
  - `autoPreserve` (default) - smart merge preserving all data
  - `serverWins` - server version wins
  - `clientWins` - client version wins with force push
  - `lastWriteWins` - latest timestamp wins
  - `merge` - custom merge function
  - `manual` - manual resolution via callback
- `TransportAdapter` interface for custom transports
- Outbox pattern for offline-first operations
- Cursor-based pagination for incremental sync
- Full resync support with configurable intervals
- Events stream for UI integration and monitoring
- `SyncStats` for sync operation statistics

