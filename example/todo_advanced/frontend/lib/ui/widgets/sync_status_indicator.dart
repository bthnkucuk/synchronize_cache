import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auto_sync.dart';
import '../../services/sync_service.dart';
import '../screens/sync_log_screen.dart';
import 'sync_panel.dart';

/// The app bar's sync summary, and the way into the sync panel.
///
/// Three facts at a glance — is it syncing, is anything queued, when is the
/// next automatic run — and a tap opens everything else.
class SyncStatusIndicator extends StatefulWidget {
  const SyncStatusIndicator({super.key});

  @override
  State<SyncStatusIndicator> createState() => _SyncStatusIndicatorState();
}

class _SyncStatusIndicatorState extends State<SyncStatusIndicator> {
  @override
  Widget build(BuildContext context) {
    return Consumer<SyncService>(
      builder: (context, syncService, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Conflict indicator
            if (syncService.conflictHandler.hasConflicts)
              _ConflictBadge(count: syncService.conflictHandler.conflictCount),

            // Status indicator, which opens the panel
            InkWell(
              onTap: () => showSyncPanel(context),
              borderRadius: BorderRadius.circular(12),
              child: _StatusBadge(
                status: syncService.status,
                pending: syncService.pendingCount,
              ),
            ),

            const SizedBox(width: 8),

            // Log button
            IconButton(
              icon: const Icon(Icons.history),
              onPressed: () => _openSyncLog(context),
              tooltip: 'Sync log',
            ),

            // Sync button
            if (syncService.isSyncing)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                icon: const Icon(Icons.sync),
                onPressed: () => _sync(context, syncService),
                tooltip: 'Sync now',
              ),
          ],
        );
      },
    );
  }

  void _openSyncLog(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const SyncLogScreen()),
    );
  }

  Future<void> _sync(BuildContext context, SyncService syncService) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final stats = await syncService.sync();
      final next = syncService.timeUntilNextAutoSync();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Synced: ${stats.pushed} sent, ${stats.pulled} received'
            '${next == null ? '' : ' — next automatic sync in '
                      '${formatCountdown(next)}'}',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } on Object {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Sync failed. Your changes are still queued.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, this.pending = 0});

  final SyncStatus status;

  /// Changes still waiting in the outbox.
  final int pending;

  @override
  Widget build(BuildContext context) {
    final (color, baseLabel, icon) = switch (status) {
      SyncStatus.idle => (Colors.green, 'Online', Icons.cloud_done),
      SyncStatus.syncing => (Colors.blue, 'Syncing', Icons.sync),
      SyncStatus.error => (Colors.red, 'Error', Icons.cloud_off),
    };
    final label = pending == 0 ? baseLabel : '$baseLabel · $pending waiting';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConflictBadge extends StatelessWidget {
  const _ConflictBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber, size: 14, color: Colors.orange),
          const SizedBox(width: 4),
          Text(
            '$count conflict${count > 1 ? 's' : ''}',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.orange,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
