import 'dart:async';

import 'package:offline_first_sync_drift/src/sync_events.dart';

/// Reporting for an engine that may have been disposed in the meantime.
extension SyncEventEmitter on StreamController<SyncEvent> {
  /// Adds [event], unless the controller was closed.
  ///
  /// `SyncEngine.dispose()` does not stop a sync that is running, and every
  /// step of one reports what it did. `add` on a closed controller throws, so
  /// that run used to fail with "Cannot add new events after calling close" —
  /// a `StateError` outside the `SyncException` hierarchy, which also replaced
  /// whatever the run itself had to say. It now finishes quietly.
  void emit(SyncEvent event) {
    if (!isClosed) add(event);
  }
}
