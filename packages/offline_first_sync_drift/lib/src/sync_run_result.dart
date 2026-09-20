import 'package:offline_first_sync_drift/src/services/push_service.dart';
import 'package:offline_first_sync_drift/src/sync_error.dart';
import 'package:offline_first_sync_drift/src/sync_events.dart';

/// Rich result model for a sync run.
class SyncRunResult {
  const SyncRunResult({
    required this.push,
    required this.pull,
    required this.stats,
    required this.duration,
    required this.kindsPushed,
    required this.kindsPulled,
    required this.stuckOpsCount,
    this.firstError,
  });

  /// One result for several per-kind runs that were started together.
  ///
  /// Counters add up; the runs were concurrent, so the duration is the
  /// longest one; the stuck count is a property of the whole outbox, so the
  /// last run's reading is the freshest.
  factory SyncRunResult.merge(List<SyncRunResult> results) {
    if (results.length == 1) return results.first;

    var pushed = 0;
    var conflicts = 0;
    var conflictsResolved = 0;
    var errors = 0;
    var pulled = 0;
    final kindsPushed = <String>{};
    final kindsPulled = <String>{};
    SyncErrorInfo? firstError;
    var duration = Duration.zero;

    for (final r in results) {
      pushed += r.push.pushed;
      conflicts += r.push.conflicts;
      conflictsResolved += r.push.conflictsResolved;
      errors += r.push.errors;
      pulled += r.pull.pulled;
      kindsPushed.addAll(r.kindsPushed);
      kindsPulled.addAll(r.kindsPulled);
      firstError ??= r.firstError;
      if (r.duration > duration) duration = r.duration;
    }

    return SyncRunResult(
      push: PushStats(
        pushed: pushed,
        conflicts: conflicts,
        conflictsResolved: conflictsResolved,
        errors: errors,
      ),
      pull: PullStats(pulled: pulled),
      stats: SyncStats(
        pushed: pushed,
        pulled: pulled,
        conflicts: conflicts,
        conflictsResolved: conflictsResolved,
        errors: errors,
      ),
      duration: duration,
      kindsPushed: kindsPushed,
      kindsPulled: kindsPulled,
      // No runs at all: an engine without tables has nothing to sync.
      stuckOpsCount: results.isEmpty ? 0 : results.last.stuckOpsCount,
      firstError: firstError,
    );
  }

  final PushStats push;
  final PullStats pull;
  final SyncStats stats;
  final Duration duration;
  final Set<String> kindsPushed;
  final Set<String> kindsPulled;
  final int stuckOpsCount;
  final SyncErrorInfo? firstError;

  bool get hadErrors => stats.errors > 0 || firstError != null;
}

final class const PullStats({required final int pulled});
