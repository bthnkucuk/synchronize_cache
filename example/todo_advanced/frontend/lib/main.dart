import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';

import 'app/device.dart';
import 'database/database.dart';
import 'repositories/note_repository.dart';
import 'repositories/settings_repository.dart';
import 'repositories/todo_repository.dart';
import 'search/app_search.dart';
import 'services/conflict_handler.dart';
import 'services/lab_actions.dart';
import 'services/sync_service.dart';
import 'sync/note_sync.dart';
import 'sync/todo_sync.dart';
import 'ui/screens/home_screen.dart';

/// Backend server URL.
///
/// Change this to your actual backend URL.
/// Default: localhost:8080 for dart_frog dev server.
///
/// For production, configure via --dart-define:
/// flutter run --dart-define=BACKEND_URL=https://api.example.com
const kBackendUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: 'http://localhost:8080',
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // On the web Flutter only builds the accessibility tree after the user opts
  // in. Enable it up front so screen readers — and browser automation such as
  // the Playwright scenario checks — can see the UI immediately.
  if (kIsWeb) {
    SemanticsBinding.instance.ensureSemantics();
  }

  // Which device this tab is. `?device=B` in the browser, or
  // `--dart-define=DEVICE=B` natively; device A keeps the original database.
  final device = Device.fromEnvironment();
  final db = AppDatabase.open(name: device.databaseName);

  // Two synced kinds, one engine.
  final todoSync = todoSyncTable(db);
  final noteSync = noteSyncTable(db);
  final todoRepo = TodoRepository(db, todoSync);
  final noteRepo = NoteRepository(db, noteSync);
  final settings = SettingsRepository(db);

  final search = AppSearch(db);
  final conflictHandler = ConflictHandler();
  final syncService = SyncService(
    db: db,
    baseUrl: kBackendUrl,
    conflictHandler: conflictHandler,
    todoSync: todoSync,
    noteSync: noteSync,
    settings: settings,
    search: search,
  );

  // Start indexing and restore this device's sync preferences. Both are
  // awaited so the first frame already shows the real state instead of
  // flipping a switch under the user a moment later.
  await search.start();
  await syncService.start();

  runApp(
    MultiProvider(
      providers: [
        Provider<Device>.value(value: device),
        Provider<AppDatabase>.value(value: db),
        Provider<TodoRepository>.value(value: todoRepo),
        Provider<NoteRepository>.value(value: noteRepo),
        Provider<SettingsRepository>.value(value: settings),
        Provider<AppSearch>.value(value: search),
        Provider<LabActions>(
          create: (_) => LabActions(backendUrl: kBackendUrl),
          dispose: (_, actions) => actions.dispose(),
        ),
        ChangeNotifierProvider<ConflictHandler>.value(value: conflictHandler),
        ChangeNotifierProvider<SyncService>.value(value: syncService),
      ],
      child: const TodoAdvancedApp(),
    ),
  );
}

/// Todo Advanced application with conflict resolution.
class TodoAdvancedApp extends StatelessWidget {
  const TodoAdvancedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Todo Advanced',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
