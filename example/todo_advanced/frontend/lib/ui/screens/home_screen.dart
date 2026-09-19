import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/device.dart';
import '../../services/conflict_handler.dart';
import '../widgets/conflict_dialog.dart';
import '../widgets/sync_status_indicator.dart';
import 'lab_screen.dart';
import 'note_list_screen.dart';
import 'search_screen.dart';
import 'todo_list_screen.dart';

/// The app shell: four destinations, one app bar, one conflict dialog.
///
/// The conflict listener sits here rather than on the todo list so a
/// conflict still reaches the user while they are on Notes or Search.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  /// Tracks if conflict dialog is currently shown to prevent duplicates.
  bool _isShowingConflictDialog = false;

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.checklist_outlined),
      selectedIcon: Icon(Icons.checklist),
      label: 'Todos',
    ),
    NavigationDestination(
      icon: Icon(Icons.sticky_note_2_outlined),
      selectedIcon: Icon(Icons.sticky_note_2),
      label: 'Notes',
    ),
    NavigationDestination(
      icon: Icon(Icons.search_outlined),
      selectedIcon: Icon(Icons.search),
      label: 'Search',
    ),
    NavigationDestination(
      icon: Icon(Icons.science_outlined),
      selectedIcon: Icon(Icons.science),
      label: 'Sync lab',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final device = context.read<Device>();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Flexible(
              child: Text('Todo Advanced', overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            // Which device you are looking at, always visible: with two tabs
            // open it is the only thing telling them apart.
            Chip(
              label: Text(device.label),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
          ],
        ),
        actions: const [SyncStatusIndicator(), SizedBox(width: 8)],
      ),
      body: Stack(
        children: [
          IndexedStack(
            index: _index,
            children: const [
              TodoListScreen(),
              NoteListScreen(),
              SearchScreen(),
              LabScreen(),
            ],
          ),

          // Conflict listener
          Consumer<ConflictHandler>(
            builder: (context, handler, _) {
              final conflict = handler.currentConflict;
              if (conflict != null && !_isShowingConflictDialog) {
                _isShowingConflictDialog = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _showConflictDialog(context, conflict);
                });
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: _destinations,
      ),
    );
  }

  Future<void> _showConflictDialog(
    BuildContext context,
    ConflictInfo conflict,
  ) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ConflictDialog(conflict: conflict),
    );
    _isShowingConflictDialog = false;
  }
}
