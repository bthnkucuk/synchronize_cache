import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/item_sync_state.dart';
import '../../services/sync_service.dart';
import 'sync_state_sheet.dart';

/// The small badge on every card saying where that one item stands.
///
/// This is the thing the whole app is really about: sync is invisible until
/// something goes wrong, and then it is too late to explain it. A chip per
/// item makes "saved here" and "saved everywhere" two different, visible
/// facts.
class SyncStateChip extends StatelessWidget {
  const SyncStateChip({
    super.key,
    required this.kind,
    required this.id,
    required this.title,
  });

  /// `todos` or `notes`.
  final String kind;
  final String id;

  /// Shown in the sheet so the user knows which item they opened.
  final String title;

  @override
  Widget build(BuildContext context) {
    // The store lives on `SyncService`, and listening to it directly keeps
    // a list of a hundred cards on one subscription instead of a hundred.
    final store = context.read<SyncService>().itemStates;

    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final state = store.stateFor(kind, id);
        final colors = _colorsFor(context, state.status);

        return Tooltip(
          message: state.status.explanation,
          child: InkWell(
            onTap: () =>
                showItemSyncSheet(context, kind: kind, id: id, title: title),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: colors.$1.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.$1.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(colors.$2, size: 13, color: colors.$1),
                  const SizedBox(width: 4),
                  Text(
                    state.status.label,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.$1,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  (Color, IconData) _colorsFor(BuildContext context, ItemSyncStatus status) {
    final scheme = Theme.of(context).colorScheme;
    return switch (status) {
      ItemSyncStatus.synced => (Colors.green.shade700, Icons.cloud_done),
      ItemSyncStatus.onlyOnThisDevice => (
        Colors.blueGrey.shade600,
        Icons.phone_iphone,
      ),
      ItemSyncStatus.changesNotSent => (
        Colors.blue.shade700,
        Icons.cloud_upload_outlined,
      ),
      ItemSyncStatus.deleteNotSent => (
        Colors.blue.shade700,
        Icons.delete_outline,
      ),
      ItemSyncStatus.waitingToRetry => (Colors.orange.shade800, Icons.schedule),
      ItemSyncStatus.stuck => (scheme.error, Icons.report_problem_outlined),
      ItemSyncStatus.conflict => (Colors.deepPurple.shade400, Icons.call_split),
    };
  }
}
