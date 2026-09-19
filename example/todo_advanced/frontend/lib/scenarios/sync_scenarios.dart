import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';
import 'package:offline_first_sync_drift_rest/offline_first_sync_drift_rest.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';
import '../sync/todo_sync.dart';
import 'recording_client.dart';
import 'scenario.dart';

const _kind = 'todos';
const _uuid = Uuid();

/// Behaviours the sync stack must guarantee, each checked against the real
/// engine — and, where a server is involved, the real demo backend.
final List<Scenario> syncScenarios = [
  const Scenario(
    id: 'K1-1',
    title: 'Deferred conflict does not spin the push loop',
    expectation:
        'When a conflict stays unresolved, sync() pushes the operation once, '
        'finishes, and leaves it in the outbox for the next sync.',
    run: _deferredConflictDoesNotSpin,
  ),
  const Scenario(
    id: 'K1-2',
    title: 'A field the user cleared stays cleared after a conflict',
    expectation:
        'Clearing the description offline while the server changes another '
        'field ends with description == null and the server change kept.',
    run: _explicitClearSurvivesConflict,
  ),
  const Scenario(
    id: 'K1-3',
    title: 'Merging lists of objects without ids does not duplicate them',
    expectation:
        'Merging two equal checklists of id-less objects keeps one copy of '
        'each item, no matter how many conflict rounds happen.',
    run: _idLessListsDoNotDuplicate,
  ),
  const Scenario(
    id: 'K1-4',
    title: 'Entity ids are encoded into the request URL',
    expectation:
        'An id such as "a#b" is sent as one encoded path segment, and the '
        'id ".." never produces a request against the collection root.',
    run: _idsAreEncodedIntoTheUrl,
  ),
  const Scenario(
    id: 'K1-6',
    title: 'A stalled server cannot hang the client forever',
    expectation:
        'With the server stalling for 6 s, a request bounded to 1 s fails '
        'after about 1 s instead of waiting for the server.',
    run: _stalledServerIsBounded,
  ),
  const Scenario(
    id: 'K1-7',
    title: 'Zone-less server timestamps do not shift the pull cursor',
    expectation:
        'A page whose last item has updated_at "2024-01-01T10:00:00.000" '
        'stores the cursor 2024-01-01T10:00:00Z in every time zone.',
    run: _zoneLessTimestampsKeepTheCursor,
  ),
];

// ---------------------------------------------------------------------------
// K1-1
// ---------------------------------------------------------------------------

Future<ScenarioOutcome> _deferredConflictDoesNotSpin(
  ScenarioContext ctx,
) async {
  // Bounds the damage if the push loop spins: the 31st request fails locally.
  final client = RecordingClient(maxRequests: 30);
  final engine = _engine(
    ctx,
    client,
    config: SyncConfig(
      conflictStrategy: ConflictStrategy.manual,
      conflictResolver: (_) async => const DeferResolution(),
    ),
  );

  try {
    final synced = await _createAndSync(
      ctx,
      engine,
      title: 'Deferred conflict',
    );
    await _editLocally(
      ctx,
      _copy(synced, title: 'Edited offline'),
      base: synced,
      changedFields: {'title'},
    );
    await _serverSidePriorityChange(ctx, synced.id, priority: 1);

    final path = '/$_kind/${synced.id}';
    final pushesBefore = client.count('PUT', path);
    final stopwatch = Stopwatch()..start();
    Object? error;
    try {
      await engine.sync(pushKinds: {_kind}, pullKinds: const {});
    } catch (e) {
      error = e;
    }
    final pushes = client.count('PUT', path) - pushesBefore;
    final pending = (await ctx.db.takeOutbox()).length;

    if (pushes == 1 && !client.guardTripped && error == null) {
      return ScenarioOutcome.pass(
        'sync() finished in ${stopwatch.elapsedMilliseconds} ms after 1 push; '
        '$pending operation(s) left in the outbox for the next sync.',
      );
    }
    return ScenarioOutcome.fail(
      'The same conflicting operation was pushed $pushes times inside ONE '
      'sync() call. The loop only stopped because the scenario guard cut the '
      'connection after 30 requests (guard tripped: ${client.guardTripped}); '
      'without it sync() never returns and the server is hit continuously.',
    );
  } finally {
    engine.dispose();
    client.close();
  }
}

// ---------------------------------------------------------------------------
// K1-2
// ---------------------------------------------------------------------------

Future<ScenarioOutcome> _explicitClearSurvivesConflict(
  ScenarioContext ctx,
) async {
  final client = RecordingClient(maxRequests: 60);
  // Default configuration: ConflictStrategy.autoPreserve.
  final engine = _engine(ctx, client, config: const SyncConfig());

  try {
    final synced = await _createAndSync(
      ctx,
      engine,
      title: 'Clear my description',
      description: 'old server note',
    );

    // The user clears the description while offline...
    await _editLocally(
      ctx,
      _copy(synced, clearDescription: true),
      base: synced,
      changedFields: {'description'},
    );
    // ...and meanwhile another client changes the priority on the server.
    await _serverSidePriorityChange(ctx, synced.id, priority: 1);

    final stats = await engine.sync();
    if (stats.conflicts == 0) {
      return const ScenarioOutcome.fail(
        'Inconclusive: the backend reported no conflict, so the merge never '
        'ran.',
      );
    }

    final local = await _localTodo(ctx, synced.id);
    final server = await _serverTodo(ctx, synced.id);
    final localDescription = local?.description;
    final serverDescription = server['description'];
    final serverPriority = server['priority'];

    final evidence =
        'conflicts=${stats.conflicts}, resolved=${stats.conflictsResolved}; '
        'local description=${_show(localDescription)}, '
        'server description=${_show(serverDescription)}, '
        'server priority=$serverPriority.';

    if (localDescription == null &&
        serverDescription == null &&
        serverPriority == 1) {
      return ScenarioOutcome.pass(
        'The cleared field stayed cleared and the concurrent server change '
        'was kept. $evidence',
      );
    }
    return ScenarioOutcome.fail(
      'The description the user deliberately cleared came back after the '
      'merge. $evidence',
    );
  } finally {
    engine.dispose();
    client.close();
  }
}

// ---------------------------------------------------------------------------
// K1-3
// ---------------------------------------------------------------------------

Future<ScenarioOutcome> _idLessListsDoNotDuplicate(ScenarioContext ctx) async {
  Map<String, Object?> payload(List<Object?> checklist) => {
    'id': 'todo-1',
    'checklist': checklist,
  };

  var checklist = <Object?>[
    <String, Object?>{'text': 'milk', 'done': false},
  ];
  final sizes = <int>[];

  for (var round = 0; round < 4; round++) {
    // Both sides hold an equal, separately decoded copy — exactly what a
    // client and a server have after a JSON round trip.
    final local = payload(_jsonCopy(checklist));
    final server = payload(_jsonCopy(checklist));
    final merged = ConflictUtils.preservingMerge(
      local,
      server,
      changedFields: {'checklist'},
    );
    checklist = merged.data['checklist']! as List<Object?>;
    sizes.add(checklist.length);
  }

  if (sizes.every((size) => size == 1)) {
    return ScenarioOutcome.pass(
      'Checklist length over 4 conflict rounds: $sizes.',
    );
  }
  return ScenarioOutcome.fail(
    'A one-item checklist grew to $sizes over 4 conflict rounds: equal '
    'objects are compared by identity, so every round appends duplicates.',
  );
}

// ---------------------------------------------------------------------------
// K1-4
// ---------------------------------------------------------------------------

Future<ScenarioOutcome> _idsAreEncodedIntoTheUrl(ScenarioContext ctx) async {
  final client = RecordingClient(maxRequests: 20);
  final transport = _transport(ctx, client);
  final now = DateTime.now().toUtc();
  final hashId = 'scenario-${_uuid.v4().substring(0, 8)}-a#b';

  try {
    await transport.push([
      UpsertOp(
        opId: _uuid.v4(),
        kind: _kind,
        id: hashId,
        localTimestamp: now,
        payloadJson: {
          'id': hashId,
          'title': 'Id with a hash',
          'completed': false,
          'priority': 3,
          'updated_at': now.toIso8601String(),
        },
      ),
    ]);
    final upsert = client.requests.last;
    final upsertTarget = Uri.decodeComponent(upsert.url.pathSegments.last);
    final upsertOk = upsertTarget == hashId && upsert.url.fragment.isEmpty;

    final requestsBeforeDots = client.requests.length;
    final dotsResult = await transport.push([
      DeleteOp(opId: _uuid.v4(), kind: _kind, id: '..', localTimestamp: now),
    ]);
    final dotRequests = client.requests.skip(requestsBeforeDots).toList();
    final dotsOk =
        dotRequests.isEmpty && dotsResult.results.single.result is PushError;

    // `runtimeType` is minified in release web builds, so name it explicitly.
    final dotsOutcome = dotsResult.results.single.result is PushError
        ? 'a PushError'
        : 'a non-error result';
    final dotsEvidence = dotRequests.isEmpty
        ? 'no request sent, reported as $dotsOutcome'
        : dotRequests.map((r) => '${r.method} <${r.url}>').join(', ');
    final evidence =
        'id "$hashId" -> ${upsert.method} <${upsert.url}> which targets the '
        'resource "$upsertTarget" | id ".." -> $dotsEvidence';

    // Best-effort cleanup of whatever entity the upsert really created.
    await http.delete(
      upsert.url.removeFragment(),
      headers: {'X-Force-Delete': 'true'},
    );

    if (upsertOk && dotsOk) {
      return ScenarioOutcome.pass(evidence);
    }
    return ScenarioOutcome.fail(
      'Requests were addressed to the wrong resource. $evidence',
    );
  } finally {
    client.close();
  }
}

// ---------------------------------------------------------------------------
// K1-6
// ---------------------------------------------------------------------------

Future<ScenarioOutcome> _stalledServerIsBounded(ScenarioContext ctx) async {
  const stall = Duration(seconds: 6);
  const bound = Duration(seconds: 1);

  final client = RecordingClient(maxRequests: 5);
  final transport = _transport(ctx, client, requestTimeout: bound);

  try {
    // A request that fails instantly (server down, CORS) is not a timeout.
    if (!await transport.health()) {
      return const ScenarioOutcome.fail(
        'Inconclusive: the backend is not reachable, so a stall cannot be '
        'simulated.',
      );
    }

    await http.post(
      Uri.parse('${ctx.backendUrl}/simulate/delay'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'milliseconds': stall.inMilliseconds, 'requests': 1}),
    );

    final stopwatch = Stopwatch()..start();
    final healthy = await transport.health();
    final elapsed = stopwatch.elapsed;

    final evidence =
        'Server stalled for ${stall.inSeconds} s, request bound '
        '${bound.inSeconds} s, health() returned $healthy after '
        '${(elapsed.inMilliseconds / 1000).toStringAsFixed(1)} s.';

    final timedOut = !healthy && elapsed >= bound * 0.8 && elapsed < bound * 2;
    if (timedOut) {
      return ScenarioOutcome.pass(evidence);
    }
    return ScenarioOutcome.fail(
      'The client waited for as long as the server stalled — a server that '
      'never answers would block sync() forever. $evidence',
    );
  } finally {
    client.close();
  }
}

// ---------------------------------------------------------------------------
// K1-7
// ---------------------------------------------------------------------------

Future<ScenarioOutcome> _zoneLessTimestampsKeepTheCursor(
  ScenarioContext ctx,
) async {
  const zoneLess = '2024-01-01T10:00:00.000';
  final expected = DateTime.utc(2024, 1, 1, 10);
  final offset = DateTime(2024, 1, 1, 10).timeZoneOffset;

  final item = <String, Object?>{
    'id': 'zone-less-1',
    'title': 'From a server without time zones',
    'completed': false,
    'priority': 3,
    'updated_at': zoneLess,
  };

  await _pullOnce(ctx, _FixedPageTransport([item]));
  final cursor = await ctx.db.getCursor(_kind);

  final evidence =
      'Device UTC offset ${_signed(offset)}; server sent "$zoneLess"; cursor '
      'stored as ${cursor?.ts.toUtc().toIso8601String()} (expected '
      '${expected.toIso8601String()}).';

  if (cursor != null && cursor.ts.isAtSameMomentAs(expected)) {
    final note = offset == Duration.zero
        ? ' (This device runs in UTC, where a time-zone shift cannot show.)'
        : '';
    return ScenarioOutcome.pass('$evidence$note');
  }
  return ScenarioOutcome.fail(
    'The cursor moved by the device UTC offset. West of UTC it jumps ahead '
    'and rows in the gap are skipped until the next full resync. $evidence',
  );
}

Future<void> _pullOnce(ScenarioContext ctx, TransportAdapter transport) async {
  final engine = SyncEngine<AppDatabase>(
    db: ctx.db,
    transport: transport,
    tables: [todoSyncTable(ctx.db)],
  );
  try {
    await engine.sync(pushKinds: const {}, pullKinds: {_kind});
  } finally {
    engine.dispose();
  }
}

/// Serves one fixed page for every pull; everything else is unused.
class _FixedPageTransport implements TransportAdapter {
  _FixedPageTransport(this._items);

  final List<Map<String, Object?>> _items;
  var _served = false;

  @override
  Future<PullPage> pull({
    required String kind,
    required DateTime updatedSince,
    required int pageSize,
    String? pageToken,
    String? afterId,
    bool includeDeleted = true,
  }) async {
    if (_served) return const PullPage(items: []);
    _served = true;
    return PullPage(items: _items);
  }

  @override
  Future<BatchPushResult> push(List<Op> ops) async =>
      const BatchPushResult(results: []);

  @override
  Future<PushResult> forcePush(Op op) async => const PushSuccess();

  @override
  Future<FetchResult> fetch({required String kind, required String id}) async =>
      const FetchNotFound();

  @override
  Future<bool> health() async => true;
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

/// Removes everything a previous scenario left in the scratch database.
Future<void> wipeScenarioDatabase(AppDatabase db) => _wipe(db);

Future<void> _wipe(AppDatabase db) async {
  await db.delete(db.todos).go();
  await db.customStatement('DELETE FROM sync_outbox');
  await db.customStatement('DELETE FROM sync_outbox_meta');
  await db.customStatement('DELETE FROM sync_cursors');
}

RestTransport _transport(
  ScenarioContext ctx,
  http.Client client, {
  Duration? requestTimeout = const Duration(seconds: 30),
}) => RestTransport(
  base: Uri.parse(ctx.backendUrl),
  token: () async => '',
  client: client,
  // Scenarios must fail fast and deterministically: no retries.
  maxRetries: 0,
  backoffMin: const Duration(milliseconds: 1),
  requestTimeout: requestTimeout,
);

SyncEngine<AppDatabase> _engine(
  ScenarioContext ctx,
  http.Client client, {
  required SyncConfig config,
}) => SyncEngine<AppDatabase>(
  db: ctx.db,
  transport: _transport(ctx, client),
  tables: [todoSyncTable(ctx.db)],
  config: config,
);

SyncEntityWriter<Todo, AppDatabase> _writer(ScenarioContext ctx) =>
    SyncWriter<AppDatabase>(ctx.db).forTable(todoSyncTable(ctx.db));

/// Creates a todo locally, pushes it, and returns the synced local row (which
/// now carries the server's `updated_at`).
Future<Todo> _createAndSync(
  ScenarioContext ctx,
  SyncEngine<AppDatabase> engine, {
  required String title,
  String? description,
}) async {
  final now = DateTime.now().toUtc();
  final todo = Todo(
    id: 'scenario-${_uuid.v4()}',
    title: title,
    description: description,
    updatedAt: now,
  );
  await _writer(ctx).insertAndEnqueue(todo, localTimestamp: now);
  await engine.sync();
  return (await _localTodo(ctx, todo.id))!;
}

Future<void> _editLocally(
  ScenarioContext ctx,
  Todo edited, {
  required Todo base,
  required Set<String> changedFields,
}) => _writer(ctx).replaceAndEnqueue(
  edited,
  baseUpdatedAt: base.updatedAt,
  changedFields: changedFields,
);

/// `Todo.copyWith` cannot clear a nullable field, so build the copy by hand.
Todo _copy(Todo todo, {String? title, bool clearDescription = false}) => Todo(
  id: todo.id,
  title: title ?? todo.title,
  description: clearDescription ? null : todo.description,
  completed: todo.completed,
  priority: todo.priority,
  dueDate: todo.dueDate,
  updatedAt: todo.updatedAt,
  deletedAt: todo.deletedAt,
  deletedAtLocal: todo.deletedAtLocal,
);

/// Another client changes the todo on the server, bumping its `updated_at`.
Future<void> _serverSidePriorityChange(
  ScenarioContext ctx,
  String id, {
  required int priority,
}) async {
  final response = await http.post(
    Uri.parse('${ctx.backendUrl}/simulate/prioritize'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'id': id, 'priority': priority}),
  );
  if (response.statusCode != 200) {
    throw StateError(
      'simulate/prioritize failed: ${response.statusCode} ${response.body}',
    );
  }
}

Future<Todo?> _localTodo(ScenarioContext ctx, String id) => (ctx.db.select(
  ctx.db.todos,
)..where((t) => t.id.equals(id))).getSingleOrNull();

Future<Map<String, dynamic>> _serverTodo(ScenarioContext ctx, String id) async {
  final response = await http.get(Uri.parse('${ctx.backendUrl}/$_kind/$id'));
  return jsonDecode(response.body) as Map<String, dynamic>;
}

List<Object?> _jsonCopy(List<Object?> value) =>
    jsonDecode(jsonEncode(value)) as List<Object?>;

String _show(Object? value) => value == null ? 'null' : '"$value"';

String _signed(Duration offset) {
  final sign = offset.isNegative ? '-' : '+';
  final hours = offset.inMinutes.abs() ~/ 60;
  final minutes = offset.inMinutes.abs() % 60;
  return '$sign${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}';
}
