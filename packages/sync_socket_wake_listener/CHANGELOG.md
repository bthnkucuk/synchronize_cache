# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-09-19

### Breaking

- The minimum SDKs are now Dart **3.13** and Flutter **3.47** (were 3.7 / 3.22).
- Requires `offline_first_sync_drift: ^0.2.0`.

### Changed

- `AppLifecycleSyncHandler` is `@immutable` and has a `const` constructor.
- Constructors use private named parameters; call sites keep the public names.
- Dependencies: `connectivity_plus` ^7.3.1, `socket_io_client` ^3.1.6,
  `drift` ^2.35.0; adds `meta`.

## [0.1.0]

- Initial version: `SocketWakeListener`, `AppLifecycleSyncHandler` and
  `NetworkSyncHandler`.
