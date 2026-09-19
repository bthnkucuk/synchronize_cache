import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:search_engine/search_engine.dart';

import '../../repositories/note_repository.dart';
import '../../repositories/todo_repository.dart';
import '../../search/app_search.dart';
import 'note_edit_screen.dart';
import 'todo_edit_screen.dart';

/// One search box over every kind in the app.
///
/// The index is FTS5 inside the same SQLite file, so it works offline and
/// keeps up on its own: a row that arrives through a pull from another
/// device shows up here without a restart.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';
  String? _kindFilter;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = context.read<AppSearch>();
    final theme = Theme.of(context);

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _controller,
              autocorrect: false,
              decoration: InputDecoration(
                hintText: 'Search todos and notes',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Clear',
                        onPressed: () {
                          _controller.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final entry in const [
                  (null, 'Everything'),
                  ('todos', 'Todos'),
                  ('notes', 'Notes'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(entry.$2),
                      selected: _kindFilter == entry.$1,
                      onSelected: (_) => setState(() => _kindFilter = entry.$1),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 8),
          _IndexStatus(search: search),
          const Divider(height: 16),

          Expanded(
            child: _query.trim().length < minimumQueryLength
                ? _Hint(theme: theme)
                : StreamBuilder<List<GlobalSearch>>(
                    stream: search.watch(
                      _query,
                      kinds: _kindFilter == null ? const {} : {_kindFilter!},
                    ),
                    builder: (context, snapshot) {
                      final hits = snapshot.data ?? const <GlobalSearch>[];
                      if (hits.isEmpty) {
                        return Center(
                          child: Text(
                            'Nothing matches "$_query".',
                            style: theme.textTheme.bodyMedium,
                          ),
                        );
                      }
                      return ListView.builder(
                        itemCount: hits.length,
                        itemBuilder: (context, index) =>
                            _HitTile(hit: hits[index]),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Type at least $minimumQueryLength letters.\n\n'
          'Search ignores Turkish letter differences: "isik" finds "ışık", '
          'and "IŞIK" finds it too.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _IndexStatus extends StatelessWidget {
  const _IndexStatus({required this.search});

  final AppSearch search;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: search.watchIndexedCount(),
      builder: (context, indexed) => StreamBuilder<int>(
        stream: search.watchPendingCount(),
        builder: (context, pending) => Text(
          '${indexed.data ?? 0} documents indexed'
          '${(pending.data ?? 0) == 0 ? '' : ', ${pending.data} waiting'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}

class _HitTile extends StatelessWidget {
  const _HitTile({required this.hit});

  final GlobalSearch hit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: Icon(
        hit.kind == 'notes'
            ? Icons.sticky_note_2_outlined
            : Icons.check_box_outlined,
      ),
      title: _Highlighted(
        value: hit.displayedTitle,
        style: theme.textTheme.titleMedium,
      ),
      subtitle: _Highlighted(
        value: hit.displayedDescription,
        style: theme.textTheme.bodySmall,
      ),
      trailing: Chip(
        label: Text(hit.kind),
        visualDensity: VisualDensity.compact,
      ),
      onTap: () => _open(context),
    );
  }

  Future<void> _open(BuildContext context) async {
    if (hit.kind == 'notes') {
      final note = await context.read<NoteRepository>().getById(hit.originalId);
      if (note == null || !context.mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => NoteEditScreen(note: note)),
      );
      return;
    }

    final todo = await context.read<TodoRepository>().getById(hit.originalId);
    if (todo == null || !context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => TodoEditScreen(todo: todo)),
    );
  }
}

/// Renders the matched runs FTS5 marked, in bold.
class _Highlighted extends StatelessWidget {
  const _Highlighted({required this.value, this.style});

  final String value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final spans = highlightSpans(value);
    if (spans.length <= 1) {
      return Text(
        value.replaceAll(highlightStart, '').replaceAll(highlightEnd, ''),
        style: style,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Text.rich(
      TextSpan(
        children: [
          for (final (text, isMatch) in spans)
            TextSpan(
              text: text,
              style: isMatch
                  ? style?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : style,
            ),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
