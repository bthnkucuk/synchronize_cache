import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/note.dart';
import '../../repositories/note_repository.dart';
import '../widgets/sync_state_chip.dart';
import 'note_edit_screen.dart';

/// The second synced kind.
///
/// Identical plumbing to the todo list — the difference is what happens when
/// two devices touch the same note: notes merge themselves, todos ask.
class NoteListScreen extends StatelessWidget {
  const NoteListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<NoteRepository>();

    return Scaffold(
      body: Column(
        children: [
          const _NotesExplainer(),
          Expanded(
            child: StreamBuilder<List<Note>>(
              stream: repo.watchAll(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final notes = snapshot.data ?? const <Note>[];
                if (notes.isEmpty) return const _EmptyState();

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: notes.length,
                  itemBuilder: (context, index) => _NoteCard(
                    key: ValueKey(notes[index].id),
                    note: notes[index],
                    repo: repo,
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-note',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const NoteEditScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add note'),
      ),
    );
  }
}

class _NotesExplainer extends StatelessWidget {
  const _NotesExplainer();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Notes merge automatically; todos ask you. If you change the title '
        'here while another device changes the body, both survive without a '
        'dialog. The sync log says which field came from where.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({super.key, required this.note, required this.repo});

  final Note note;
  final NoteRepository repo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => NoteEditScreen(note: note)),
        ),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(note.title, style: theme.textTheme.titleMedium),
                    if (note.body != null && note.body!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        note.body!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    SyncStateChip(
                      kind: 'notes',
                      id: note.id,
                      title: note.title,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  note.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                ),
                tooltip: note.pinned ? 'Unpin' : 'Pin',
                onPressed: () => repo.togglePinned(note),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete',
                onPressed: () => _delete(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete note'),
        content: Text('Delete "${note.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await repo.delete(note);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.sticky_note_2_outlined,
            size: 72,
            color: theme.colorScheme.primary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text('No notes yet', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Notes are the second synced kind — add one and watch it appear '
            'on the other device.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
