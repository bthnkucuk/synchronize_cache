import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auto_sync.dart';
import '../../services/live_updates.dart';
import '../../services/sync_service.dart';

/// Opens the sync panel as a bottom sheet.
Future<void> showSyncPanel(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => const SyncPanel(),
);

/// "When will it sync, and how do I make it sync now?"
///
/// Everything the reader needs to predict the app's behaviour is on this one
/// sheet: what is queued, when the next automatic run is due, whether writes
/// go out immediately, and the four buttons that do it by hand.
class SyncPanel extends StatefulWidget {
  const SyncPanel({super.key});

  @override
  State<SyncPanel> createState() => _SyncPanelState();
}

class _SyncPanelState extends State<SyncPanel> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // The countdown is derived, not stored, so it only needs a repaint.
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Consumer<SyncService>(
      builder: (context, sync, _) {
        final remaining = sync.timeUntilNextAutoSync();
        final last = sync.lastSync;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sync', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 12),

                  _StatusLine(sync: sync),
                  const SizedBox(height: 4),
                  Text(
                    '${sync.pendingCount} change(s) waiting to be sent'
                    '${sync.stuckCount == 0 ? '' : ', ${sync.stuckCount} stuck'}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (last != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Last: ${last.headline} at ${_time(last.at)}'
                      '${last.firstError == null ? '' : ' — '
                                '${last.firstError!.words}'}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],

                  const Divider(height: 28),

                  // --- Automatic sync -----------------------------------
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: sync.autoSync.enabled,
                    onChanged: (value) => sync.setAutoSync(
                      sync.autoSync.copyWith(enabled: value),
                    ),
                    title: const Text('Automatic sync'),
                    subtitle: Text(
                      sync.autoSync.enabled
                          ? (remaining == null
                                ? 'Starting…'
                                : 'Next automatic sync in '
                                      '${formatCountdown(remaining)}')
                          : 'Automatic sync is off — changes stay on this '
                                'device until you press Send now',
                    ),
                  ),
                  if (sync.autoSync.enabled)
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final interval in autoSyncIntervals)
                          ChoiceChip(
                            label: Text(describeInterval(interval)),
                            selected: sync.autoSync.interval == interval,
                            onSelected: (_) => sync.setAutoSync(
                              sync.autoSync.copyWith(interval: interval),
                            ),
                          ),
                      ],
                    ),

                  const Divider(height: 28),

                  // --- Push on change -----------------------------------
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: sync.pushOnChange,
                    onChanged: (value) => sync.setPushOnChange(value: value),
                    title: const Text('Send right after every change'),
                    subtitle: Text(
                      'Waits ${sync.pushDebounce.inMilliseconds} ms after '
                      'your last edit, so a burst of edits becomes one '
                      'request. Receiving still waits for a sync.',
                    ),
                  ),

                  // --- Live updates -------------------------------------
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: sync.live.enabled,
                    onChanged: (value) => sync.setLiveUpdates(value: value),
                    title: const Text('Live updates'),
                    subtitle: Text(
                      sync.live.enabled
                          ? '${sync.live.description}. A change on another '
                                'device arrives within a second.'
                          : 'Off — another device\'s change only arrives at '
                                'the next automatic sync or Get changes.',
                    ),
                  ),

                  const Divider(height: 28),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: sync.isSyncing
                            ? null
                            : () => _run(context, sync.sendNow, 'Send now'),
                        icon: const Icon(Icons.upload),
                        label: const Text('Send now'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: sync.isSyncing
                            ? null
                            : () =>
                                  _run(context, sync.getChanges, 'Get changes'),
                        icon: const Icon(Icons.download),
                        label: const Text('Get changes'),
                      ),
                      OutlinedButton.icon(
                        onPressed: sync.isSyncing
                            ? null
                            : () => _run(context, sync.sync, 'Sync now'),
                        icon: const Icon(Icons.sync),
                        label: const Text('Sync now'),
                      ),
                      OutlinedButton.icon(
                        onPressed: sync.isSyncing
                            ? null
                            : () =>
                                  _run(context, sync.fullResync, 'Full resync'),
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('Full resync'),
                      ),
                    ],
                  ),

                  if (sync.stuckCount > 0) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: () => _retryStuck(context, sync),
                          icon: const Icon(Icons.refresh),
                          label: Text('Retry stuck (${sync.stuckCount})'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _discardStuck(context, sync),
                          icon: const Icon(Icons.delete_sweep_outlined),
                          label: const Text('Discard stuck'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _run(
    BuildContext context,
    Future<Object?> Function() action,
    String what,
  ) async {
    // Read both before awaiting: this sheet can be dismissed mid-sync.
    final messenger = ScaffoldMessenger.of(context);
    final sync = context.read<SyncService>();
    try {
      await action();
      messenger.showSnackBar(
        SnackBar(
          content: Text(sync.lastSync?.headline ?? '$what finished'),
          duration: const Duration(seconds: 3),
        ),
      );
    } on Object {
      messenger.showSnackBar(
        SnackBar(
          content: Text('$what failed. The changes are still queued.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _retryStuck(BuildContext context, SyncService sync) async {
    await sync.retryStuck();
    if (!context.mounted) return;
    await _run(context, sync.sendNow, 'Retry stuck');
  }

  Future<void> _discardStuck(BuildContext context, SyncService sync) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Discard ${sync.stuckCount} stuck change(s)?'),
        content: const Text(
          'They are thrown away for good. This device keeps what it shows, '
          'but the server never learns about these changes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed == true) await sync.discardStuck();
  }

  static String _time(DateTime value) {
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.sync});

  final SyncService sync;

  @override
  Widget build(BuildContext context) {
    final (icon, color, text) = switch (sync.live.state) {
      LiveUpdatesState.connected => (
        Icons.bolt,
        Colors.green.shade700,
        sync.live.description,
      ),
      LiveUpdatesState.connecting || LiveUpdatesState.reconnecting => (
        Icons.sync_problem,
        Colors.orange.shade800,
        sync.live.description,
      ),
      LiveUpdatesState.off => (
        Icons.cloud_off,
        Theme.of(context).colorScheme.onSurfaceVariant,
        sync.live.description,
      ),
    };

    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
