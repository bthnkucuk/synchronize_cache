# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-09-19

### Breaking

- The minimum Dart SDK is now **3.13** (was 3.7).
- `GlobalSearch` and `PendingSearchItem` no longer extend `Equatable`; the
  `equatable` dependency is gone. `==`, `hashCode` and `toString` are
  hand-written and keep value semantics — `PendingSearchItem.data` is still
  compared deeply, as decoded JSON — but `props` and `stringify` are no longer
  part of the public API.
- `toString()` now always lists the fields. With Equatable that only happened
  in debug builds.

### Changed

- Dependencies: `drift` ^2.35.0, `synchronized` ^3.4.2; adds `meta`.

## [0.1.0]

- Initial version: FTS5-backed search index, pending queue, cursor-based
  incremental indexing and a swappable transport layer.
