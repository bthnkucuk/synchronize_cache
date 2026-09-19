@Tags(['widget'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:todo_advanced_frontend/database/database.dart';
import 'package:todo_advanced_frontend/repositories/todo_repository.dart';
import 'package:todo_advanced_frontend/services/conflict_handler.dart';
import 'package:todo_advanced_frontend/services/sync_service.dart';
import 'package:todo_advanced_frontend/sync/todo_sync.dart';
import 'package:todo_advanced_frontend/ui/screens/todo_list_screen.dart';
import 'package:todo_advanced_frontend/ui/widgets/sync_state_chip.dart';
import 'package:todo_advanced_frontend/ui/widgets/sync_status_indicator.dart';

import '../helpers/test_database.dart';

/// Widget tests for TodoListScreen in advanced mode.
///
/// These tests verify that UI updates correctly when data changes,
/// including conflict handling UI.
/// Run with: `flutter test test/widget/ --tags widget`
void main() {
  late AppDatabase db;
  late TodoRepository repo;
  late ConflictHandler conflictHandler;
  late SyncService syncService;

  setUp(() {
    db = createTestDatabase();
    final todoSync = todoSyncTable(db);
    repo = TodoRepository(db, todoSync);
    conflictHandler = ConflictHandler();
    syncService = SyncService(
      db: db,
      baseUrl: 'http://localhost:8080',
      conflictHandler: conflictHandler,
      todoSync: todoSync,
    );
  });

  tearDown(() async {
    syncService.dispose();
    await db.close();
  });

  Widget createApp() {
    return MultiProvider(
      providers: [
        Provider.value(value: repo),
        ChangeNotifierProvider.value(value: syncService),
        ChangeNotifierProvider.value(value: conflictHandler),
      ],
      // `TodoListScreen` is one destination inside `HomeScreen`, which owns
      // the app bar; recreate just that chrome here.
      child: MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: const Text('Todo Advanced'),
            actions: const [SyncStatusIndicator()],
          ),
          body: const TodoListScreen(),
        ),
      ),
    );
  }

  /// Helper to properly cleanup widget and allow timers to settle.
  Future<void> cleanupWidget(WidgetTester tester) async {
    // Pump empty widget to trigger dispose and allow Drift timers to complete
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('TodoListScreen Widget Tests (Advanced)', () {
    testWidgets('shows empty state when no todos', (tester) async {
      await tester.pumpWidget(createApp());
      await tester.pumpAndSettle();

      expect(find.text('No todos yet'), findsOneWidget);
      expect(find.text('Add Todo'), findsOneWidget);

      await cleanupWidget(tester);
    });

    testWidgets('shows todo after creation via repo', (tester) async {
      await tester.pumpWidget(createApp());
      await tester.pumpAndSettle();

      // Verify empty state first
      expect(find.text('No todos yet'), findsOneWidget);

      // Create todo directly via repo
      await repo.create(title: 'Widget Test Todo');
      await tester.pumpAndSettle();

      // Verify todo appears
      expect(find.text('Widget Test Todo'), findsOneWidget);
      expect(find.text('No todos yet'), findsNothing);

      await cleanupWidget(tester);
    });

    testWidgets('updates UI when todo is toggled via checkbox', (tester) async {
      await tester.pumpWidget(createApp());

      // Create an incomplete todo
      await repo.create(title: 'Complete Me', completed: false);
      await tester.pumpAndSettle();

      // Find and verify checkbox is unchecked
      final checkboxFinder = find.byType(Checkbox);
      expect(checkboxFinder, findsOneWidget);

      var checkbox = tester.widget<Checkbox>(checkboxFinder);
      expect(checkbox.value, isFalse);

      // Toggle via checkbox
      await tester.tap(checkboxFinder);
      await tester.pumpAndSettle();

      // Verify checkbox is now checked
      checkbox = tester.widget<Checkbox>(checkboxFinder);
      expect(checkbox.value, isTrue);

      await cleanupWidget(tester);
    });

    testWidgets('removes todo from list after delete via repo', (tester) async {
      await tester.pumpWidget(createApp());

      // Create todo
      final todo = await repo.create(title: 'Delete Me');
      await tester.pumpAndSettle();

      expect(find.text('Delete Me'), findsOneWidget);

      // Delete via repo (simulates background sync or direct action)
      await repo.delete(todo);
      await tester.pumpAndSettle();

      // Verify todo is gone
      expect(find.text('Delete Me'), findsNothing);

      await cleanupWidget(tester);
    });

    testWidgets('shows sync status indicator with Online badge', (
      tester,
    ) async {
      await tester.pumpWidget(createApp());
      await tester.pumpAndSettle();

      // Initial state: cloud_done icon (Online status)
      expect(find.byIcon(Icons.cloud_done), findsOneWidget);
      expect(find.text('Online'), findsOneWidget);

      // Sync button available
      expect(find.byIcon(Icons.sync), findsOneWidget);

      await cleanupWidget(tester);
    });

    testWidgets('shows strikethrough for completed todo', (tester) async {
      await tester.pumpWidget(createApp());

      // Create a completed todo
      await repo.create(title: 'Completed Task', completed: true);
      await tester.pumpAndSettle();

      // Find Text widget with lineThrough decoration
      final textFinder = find.text('Completed Task');
      expect(textFinder, findsOneWidget);

      // Get the Text widget and check decoration
      final text = tester.widget<Text>(textFinder);
      expect(text.style?.decoration, TextDecoration.lineThrough);

      await cleanupWidget(tester);
    });

    testWidgets('shows todo with description', (tester) async {
      await tester.pumpWidget(createApp());

      await repo.create(
        title: 'With Description',
        description: 'This is a test description',
      );
      await tester.pumpAndSettle();

      expect(find.text('With Description'), findsOneWidget);
      expect(find.text('This is a test description'), findsOneWidget);

      await cleanupWidget(tester);
    });

    testWidgets('shows the add button', (tester) async {
      await tester.pumpWidget(createApp());
      await tester.pumpAndSettle();

      // The server simulations moved to the Sync lab, so one FAB is left.
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('Add Todo'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);

      await cleanupWidget(tester);
    });

    testWidgets('every card carries a sync state chip', (tester) async {
      await tester.pumpWidget(createApp());
      await repo.create(title: 'Never sent');
      await tester.pumpAndSettle();

      // The chip renders for every row. Which state it shows is decided by
      // `deriveItemSyncStates`, covered exhaustively in
      // test/services/item_sync_state_test.dart — a widget test cannot keep
      // the outbox subscription alive, because `pumpAndSettle` runs in a
      // fake-async zone that never completes real database I/O.
      expect(find.byType(SyncStateChip), findsOneWidget);
      expect(find.text('Synced'), findsOneWidget);

      await cleanupWidget(tester);
    });

    testWidgets('multiple todos appear in list', (tester) async {
      await tester.pumpWidget(createApp());
      await tester.pumpAndSettle();

      // Create multiple todos
      await repo.create(title: 'Todo 1');
      await repo.create(title: 'Todo 2');
      await repo.create(title: 'Todo 3');
      await tester.pumpAndSettle();

      // All should be visible
      expect(find.text('Todo 1'), findsOneWidget);
      expect(find.text('Todo 2'), findsOneWidget);
      expect(find.text('Todo 3'), findsOneWidget);

      // ListView should be present
      expect(find.byType(ListView), findsOneWidget);

      await cleanupWidget(tester);
    });

    testWidgets('shows delete button on each todo card', (tester) async {
      await tester.pumpWidget(createApp());

      await repo.create(title: 'Has Delete Button');
      await tester.pumpAndSettle();

      // Find delete icon button
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);

      await cleanupWidget(tester);
    });

    testWidgets('real-time update when todo is updated', (tester) async {
      await tester.pumpWidget(createApp());

      // Create todo
      final todo = await repo.create(title: 'Original Title');
      await tester.pumpAndSettle();

      expect(find.text('Original Title'), findsOneWidget);

      // Update via repo
      await repo.update(todo, title: 'Updated Title');
      await tester.pumpAndSettle();

      // Old title gone, new title appears
      expect(find.text('Original Title'), findsNothing);
      expect(find.text('Updated Title'), findsOneWidget);

      await cleanupWidget(tester);
    });

    testWidgets('the status badge opens the sync panel', (tester) async {
      await tester.pumpWidget(createApp());
      await tester.pumpAndSettle();

      expect(find.text('Online'), findsOneWidget);

      await tester.tap(find.text('Online'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Automatic sync'), findsOneWidget);
      expect(find.text('Send now'), findsOneWidget);
      expect(find.text('Get changes'), findsOneWidget);

      await cleanupWidget(tester);
    });
  });
}
