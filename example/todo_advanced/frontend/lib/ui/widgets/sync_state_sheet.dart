import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auto_sync.dart';
import '../../services/item_sync_state.dart';
import '../../services/sync_service.dart';

/// Opens "What happens next?" for one item.
Future<void> showItemSyncSheet(
  BuildContext context, {
  required String kind,
  required String id,
  required String title,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ItemSyncSheet(kind: kind, id: id, title: title),
  );
}

class _ItemSyncSheet extends StatelessWidget {
  const _ItemSyncSheet({
    required this.kind,
    required this.id,
    required this.title,
  });

  final String kind;
  final String id;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final sync = context.read<SyncService>();

    return ListenableBuilder(
      listenable: sync.itemStates,
      builder: (context, _) {
        final state = sync.itemStates.stateFor(kind, id);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('What happens next?', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    '$title · $kind',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),

                  Text(state.status.label, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    state.status.explanation,
                    style: theme.textTheme.bodyMedium,
                  ),

                  if (state.reason != null) ...[
                    const SizedBox(height: 12),
                    _Callout(
                      icon: Icons.info_outline,
                      text:
                          'Last attempt: ${state.reason!.words}.'
                          '${state.reason!.environmental ? ' That is not '
                                    'this item\'s fault, so it was not counted '
                                    'as an attempt.' : ''}',
                    ),
                  ],

                  const SizedBox(height: 16),
                  Text(
                    'When will it be sent?',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _whenSentence(sync, state),
                    style: theme.textTheme.bodyMedium,
                  ),

                  if (state.operations.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      'Queued operations',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    for (final op in state.operations)
                      _OperationTile(op: op, maxTryCount: state.maxTryCount),
                  ],

                  if (state.status == ItemSyncStatus.stuck) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: () => _retry(context, sync),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: () => _discard(context, sync),
                          icon: const Icon(Icons.delete_sweep_outlined),
                          label: const Text('Discard change'),
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

  /// The one sentence the brief asks for: when does this actually leave?
  String _whenSentence(SyncService sync, ItemSyncState state) {
    if (state.isSynced) {
      return 'Nothing is waiting — it is already on the server.';
    }
    if (state.status == ItemSyncStatus.conflict) {
      return 'Nothing will be sent until you answer the conflict dialog.';
    }
    if (state.status == ItemSyncStatus.stuck) {
      return 'It will not be tried again on its own. Use Retry to put it '
          'back in the queue, or Discard change to throw it away.';
    }

    final parts = <String>[];
    if (sync.pushOnChange) {
      parts.add(
        'Send right after every change is on, so it goes out about '
        '${sync.pushDebounce.inMilliseconds} ms after your last edit',
      );
    }
    final remaining = sync.timeUntilNextAutoSync();
    if (remaining != null) {
      parts.add(
        'the next automatic sync is in ${formatCountdown(remaining)} '
        '(${describeInterval(sync.autoSync.interval)})',
      );
    }
    if (parts.isEmpty) {
      return 'Automatic sync is off and changes are not sent on write, so '
          'this stays on this device until you press Send now.';
    }
    return '${parts.join('; ')}. Send now does it immediately.';
  }

  Future<void> _retry(BuildContext context, SyncService sync) async {
    Navigator.pop(context);
    await sync.retryStuck();
    try {
      await sync.sendNow();
    } on Object {
      // The sync panel already reports the failure; nothing to add here.
    }
  }

  Future<void> _discard(BuildContext context, SyncService sync) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard this change?'),
        content: const Text(
          'The queued change is thrown away. What you see on this device '
          'stays as it is, but the server will never learn about it — the '
          'next time you receive changes, it will be overwritten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it queued'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    Navigator.pop(context);
    await sync.discardStuck();
  }
}

class _OperationTile extends StatelessWidget {
  const _OperationTile({required this.op, required this.maxTryCount});

  final QueuedOperation op;
  final int maxTryCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final changed = op.changedFields;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(op.typeLabel, style: theme.textTheme.titleSmall),
                const Spacer(),
                Text(
                  'attempts ${op.tryCount} of $maxTryCount',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Queued ${_time(op.queuedAt)}'
              '${op.lastTriedAt == null ? '' : ', last tried '
                        '${_time(op.lastTriedAt!)}'}',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              op.baseUpdatedAt == null
                  ? 'Based on: nothing — the server has never seen this row'
                  : 'Based on the server version of '
                        '${_time(op.baseUpdatedAt!)}',
              style: theme.textTheme.bodySmall,
            ),
            if (changed != null && changed.isNotEmpty)
              Text(
                'Changed fields: ${changed.join(', ')}',
                style: theme.textTheme.bodySmall,
              ),
            if (op.lastError != null) ...[
              const SizedBox(height: 4),
              Text(
                op.lastError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _time(DateTime value) {
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}

class _Callout extends StatelessWidget {
  const _Callout({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
