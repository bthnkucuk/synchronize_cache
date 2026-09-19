# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

### Fixed

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

