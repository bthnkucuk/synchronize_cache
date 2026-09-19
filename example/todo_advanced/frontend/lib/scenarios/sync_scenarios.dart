import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
// The app's generated database declares its own companions for the sync
// tables; those are the ones that fit `db.syncOutbox`.
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart'
    hide SyncOutboxCompanion;
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
  const Scenario(
    id: 'K1-7c',
    title: 'An empty page that names a next page is not the end of a pull',
    expectation:
        'When the server answers the first page with no items but a next '
        'page token, the pull follows the token and still stores the rows '
        'behind it.',
    run: _emptyPageWithNextTokenIsFollowed,
  ),
  const Scenario(
    id: 'K1-8',
    title: 'A 409 without the current record is an error, not a conflict',
    expectation:
        'A 409 whose body carries no record (a proxy or a default error '
        'handler) must not be "resolved" against made-up server data: no '
        'forced overwrite is sent, the operation stays queued and the next '
        'sync delivers it.',
    run: _bareConflictIsNotResolved,
  ),
  const Scenario(
    id: 'K1-10',
    title: 'Your own edits never conflict with yourself',
    expectation:
        'With nobody else writing, an edit after sync — and then two quick '
        'edits pushed by a single sync — are accepted without any conflict, '
        'although the app stamps updatedAt with "now" on every edit.',
    run: _ownEditsDoNotConflict,
  ),
  const Scenario(
    id: 'K1-11',
    title: 'Being offline or signed out never parks your queued writes',
    expectation:
        'A write queued while the server is unreachable for $_failedSyncs '
        'syncs, and then rejected with 401 for $_failedSyncs more, is not '
        'counted as a failed attempt of that write: it is never reported as '
        'stuck and is delivered by the first sync that gets through.',
    run: _outagesDoNotParkWrites,
  ),
  const Scenario(
    id: 'K2-43',
    title: 'A delete made on another device reaches this one',
    expectation:
        'After another client deletes a synced todo, the next pull marks the '
        'local row as deleted, so the app stops showing it.',
    run: _remoteDeleteArrives,
  ),
  const Scenario(
    id: 'P1',
    title: 'Outbox queries use indexes, also on a database from before them',
    expectation:
        'On a database created without the outbox indexes, the first sync '
        'adds them; with $_queuedOps operations queued, taking a batch and '
        're-basing an entity read the queue through an index instead of '
        'scanning and sorting it.',
    run: _outboxQueriesAreIndexed,
  ),
  const Scenario(
    id: 'P3',
    title: 'A pushed batch is written back in one transaction',
    expectation:
        'After pushing $_batchOps operations in one batch, the server rows, '
        'the acknowledgement and the re-base are committed together: one '
        'transaction instead of one commit per statement.',
    run: _batchIsCommittedOnce,
  ),
];

const _queuedOps = 5000;
const _batchOps = 25;
const _failedSyncs = 6;

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

// ---------------------------------------------------------------------------
// K1-7c
// ---------------------------------------------------------------------------

Future<ScenarioOutcome> _emptyPageWithNextTokenIsFollowed(
  ScenarioContext ctx,
) async {
  final client = RecordingClient(maxRequests: 40);
  final engine = _engine(ctx, client, config: const SyncConfig());

  try {
    // Two todos that exist on the server only: the client has to pull them.
    final ids = <String>[];
    for (final title in [
      'Behind the empty page 1',
      'Behind the empty page 2',
    ]) {
      final id = 'scenario-${_uuid.v4()}';
      ids.add(id);
      final response = await http.post(
        Uri.parse('${ctx.backendUrl}/$_kind'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id': id, 'title': title}),
      );
      if (response.statusCode >= 300) {
        throw StateError('creating a todo failed: ${response.statusCode}');
      }
    }

    await _simulate(ctx, 'empty_page', {'pages': 1});
    await engine.sync(pushKinds: const {}, pullKinds: {_kind});

    final pulls = client.requests
        .where((r) => r.method == 'GET' && r.url.path.endsWith('/$_kind'))
        .toList();
    final followed = pulls.any(
      (r) => r.url.queryParameters['pageToken'] == 'after-the-empty-page',
    );
    final local = [
      for (final id in ids)
        if (await _localTodo(ctx, id) != null) id,
    ];

    final evidence =
        'The first page was empty with nextPageToken="after-the-empty-page"; '
        'the client sent ${pulls.length} list request(s), followed the '
        'token: $followed; ${local.length} of ${ids.length} server rows '
        'arrived locally.';

    if (followed && local.length == ids.length) {
      return ScenarioOutcome.pass(evidence);
    }
    return ScenarioOutcome.fail(
      'The pull stopped at the empty page. Rows behind it are never '
      'downloaded: the cursor does not move, so every later sync stops at '
      'the same place. $evidence',
    );
  } finally {
    engine.dispose();
    client.close();
  }
}

// ---------------------------------------------------------------------------
// K1-8
// ---------------------------------------------------------------------------

Future<ScenarioOutcome> _bareConflictIsNotResolved(ScenarioContext ctx) async {
  final client = RecordingClient(maxRequests: 40);
  // Default configuration: ConflictStrategy.autoPreserve.
  final engine = _engine(ctx, client, config: const SyncConfig());

  try {
    final synced = await _createAndSync(ctx, engine, title: 'Original title');
    await _editLocally(
      ctx,
      _copy(synced, title: 'Edited offline'),
      base: synced,
      changedFields: {'title'},
    );

    await _simulate(ctx, 'bare_conflict', {'requests': 1});
    final requestsBefore = client.requests.length;
    final stats = await engine.sync(pushKinds: {_kind}, pullKinds: const {});

    final forced = client.requests
        .skip(requestsBefore)
        .where((r) => r.headers.containsKey('X-Force-Update'))
        .length;
    final queuedAfterFirst = (await ctx.db.takeOutbox()).length;
    final serverAfterFirst = (await _serverTodo(ctx, synced.id))['title'];

    // Nothing is simulated any more: the queued edit must simply go through.
    final retry = await engine.sync(pushKinds: {_kind}, pullKinds: const {});
    final queuedAfterRetry = (await ctx.db.takeOutbox()).length;
    final serverAfterRetry = (await _serverTodo(ctx, synced.id))['title'];

    final evidence =
        'Server answered 409 {"error":"conflict"}. First sync: '
        'conflicts=${stats.conflicts}, resolved=${stats.conflictsResolved}, '
        'errors=${stats.errors}, forced overwrites sent=$forced, '
        '$queuedAfterFirst op(s) still queued, server title='
        '"$serverAfterFirst". Next sync: pushed=${retry.pushed}, '
        '$queuedAfterRetry op(s) queued, server title="$serverAfterRetry".';

    final treatedAsError =
        stats.conflicts == 0 &&
        stats.errors == 1 &&
        forced == 0 &&
        queuedAfterFirst == 1 &&
        serverAfterFirst == 'Original title';
    final delivered =
        retry.pushed == 1 &&
        queuedAfterRetry == 0 &&
        serverAfterRetry == 'Edited offline';

    if (treatedAsError && delivered) {
      return ScenarioOutcome.pass(evidence);
    }
    return ScenarioOutcome.fail(
      'The error body was taken for the server\'s record: a conflict was '
      '"resolved" against data the server never sent, and the result was '
      'forced onto the server past its version check. $evidence',
    );
  } finally {
    engine.dispose();
    client.close();
  }
}

// ---------------------------------------------------------------------------
// K1-10
// ---------------------------------------------------------------------------

Future<ScenarioOutcome> _ownEditsDoNotConflict(ScenarioContext ctx) async {
  final client = RecordingClient(maxRequests: 60);
  // Every conflict in this scenario is spurious, so count them instead of
  // letting autoPreserve resolve them out of sight.
  var conflicts = 0;
  final engine = _engine(
    ctx,
    client,
    config: SyncConfig(
      conflictStrategy: ConflictStrategy.manual,
      conflictResolver: (_) async {
        conflicts++;
        return const AcceptClient();
      },
    ),
  );

  try {
    final synced = await _createAndSync(ctx, engine, title: 'Mine alone');

    await _editLikeTheApp(ctx, synced.id, title: 'First edit');
    await engine.sync();
    final afterOneEdit = conflicts;

    await _editLikeTheApp(ctx, synced.id, title: 'Second edit');
    await _editLikeTheApp(ctx, synced.id, title: 'Third edit');
    await engine.sync();
    final afterTwoQuickEdits = conflicts - afterOneEdit;

    final server = await _serverTodo(ctx, synced.id);
    final pending = (await ctx.db.takeOutbox()).length;
    final evidence =
        'Conflicts after one edit: $afterOneEdit; after two quick edits in '
        'one sync: $afterTwoQuickEdits; server title="${server['title']}"; '
        '$pending operation(s) left in the outbox.';

    if (conflicts == 0 && server['title'] == 'Third edit' && pending == 0) {
      return ScenarioOutcome.pass(evidence);
    }
    return ScenarioOutcome.fail(
      'The server rejected this client\'s own edits as conflicts although '
      'nobody else wrote to the todo. $evidence',
    );
  } finally {
    engine.dispose();
    client.close();
  }
}

/// Edits the way `TodoRepository.update` does: the new row is stamped with
/// "now", and the version that was edited is passed as the base.
Future<void> _editLikeTheApp(
  ScenarioContext ctx,
  String id, {
  required String title,
}) async {
  final before = (await _localTodo(ctx, id))!;
  await _writer(ctx).replaceAndEnqueue(
    Todo(
      id: before.id,
      title: title,
      description: before.description,
      completed: before.completed,
      priority: before.priority,
      dueDate: before.dueDate,
      updatedAt: DateTime.now().toUtc(),
    ),
    baseUpdatedAt: before.updatedAt,
    changedFields: {'title'},
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
// K1-11
// ---------------------------------------------------------------------------

Future<ScenarioOutcome> _outagesDoNotParkWrites(ScenarioContext ctx) async {
  final client = RecordingClient(maxRequests: 80);
  const config = SyncConfig();
  RestTransport transportTo(String url) => RestTransport(
    base: Uri.parse(url),
    token: () async => '',
    client: client,
    maxRetries: 0,
    backoffMin: const Duration(milliseconds: 1),
    requestTimeout: const Duration(seconds: 2),
  );
  SyncEngine<AppDatabase> engineFor(String url) => SyncEngine<AppDatabase>(
    db: ctx.db,
    transport: transportTo(url),
    tables: [todoSyncTable(ctx.db)],
    config: config,
  );

  // Nothing listens on the discard port: what a device without a network
  // sees from the browser's point of view.
  final offline = engineFor('http://localhost:9');
  final online = engineFor(ctx.backendUrl);

  try {
    // The first sync of a database is a full resync; do it while online.
    await online.sync();

    final now = DateTime.now().toUtc();
    final todo = Todo(
      id: 'scenario-${_uuid.v4()}',
      title: 'Written without a connection',
      updatedAt: now,
    );
    await _writer(ctx).insertAndEnqueue(todo, localTimestamp: now);

    Future<void> failing(SyncEngine<AppDatabase> engine) async {
      for (var i = 0; i < _failedSyncs; i++) {
        try {
          await engine.sync(pushKinds: {_kind}, pullKinds: const {});
        } catch (_) {
          // A transport may throw instead of reporting per operation.
        }
      }
    }

    await failing(offline);
    final stuckAfterOffline = (await online.getStuckOperations()).length;

    await _simulate(ctx, 'fail_writes', {
      'status': 401,
      'requests': _failedSyncs,
    });
    await failing(online);
    await _simulate(ctx, 'fail_writes', {'status': 401, 'requests': 0});
    final stuckAfter401 = (await online.getStuckOperations()).length;

    final attempts = await ctx.db
        .customSelect('SELECT try_count FROM sync_outbox')
        .get();
    final tryCount = attempts.isEmpty
        ? null
        : attempts.first.read<int>('try_count');

    final recovery = await online.sync(pushKinds: {_kind}, pullKinds: const {});
    final queued = (await ctx.db.takeOutbox(limit: 10)).length;
    final response = await http.get(
      Uri.parse('${ctx.backendUrl}/$_kind/${todo.id}'),
    );

    final evidence =
        '$_failedSyncs syncs without a network, then $_failedSyncs syncs '
        'answered 401 (budget: ${config.maxOutboxTryCount} attempts). Counted '
        'attempts afterwards: ${tryCount ?? 'op gone'}; reported stuck: '
        '$stuckAfterOffline after the outage, $stuckAfter401 after the 401s. '
        'First healthy sync: pushed=${recovery.pushed}, $queued op(s) still '
        'queued, server has the todo: ${response.statusCode == 200}.';

    if (recovery.pushed == 1 &&
        queued == 0 &&
        response.statusCode == 200 &&
        stuckAfterOffline == 0 &&
        stuckAfter401 == 0) {
      return ScenarioOutcome.pass(evidence);
    }
    return ScenarioOutcome.fail(
      'The write was parked as "stuck" although nothing was wrong with it: it '
      'is never sent again unless the app calls retryStuckOperations(). '
      '$evidence',
    );
  } finally {
    offline.dispose();
    online.dispose();
    client.close();
  }
}

// ---------------------------------------------------------------------------
// K2-43
// ---------------------------------------------------------------------------

Future<ScenarioOutcome> _remoteDeleteArrives(ScenarioContext ctx) async {
  final client = RecordingClient(maxRequests: 40);
  final engine = _engine(ctx, client, config: const SyncConfig());

  try {
    final synced = await _createAndSync(
      ctx,
      engine,
      title: 'Deleted elsewhere',
    );

    // Another device deletes the todo.
    final deleted = await http.delete(
      Uri.parse('${ctx.backendUrl}/$_kind/${synced.id}'),
    );
    if (deleted.statusCode >= 300) {
      throw StateError('DELETE failed: ${deleted.statusCode}');
    }

    final stats = await engine.sync(pushKinds: const {}, pullKinds: {_kind});
    final local = await _localTodo(ctx, synced.id);
    final visible =
        await (ctx.db.select(ctx.db.todos)..where(
              (t) =>
                  t.id.equals(synced.id) &
                  t.deletedAt.isNull() &
                  t.deletedAtLocal.isNull(),
            ))
            .get();

    final evidence =
        'The server answered the DELETE with ${deleted.statusCode}; the pull '
        'brought ${stats.pulled} row(s); local deletedAt='
        '${local?.deletedAt?.toIso8601String()}; still shown by the app: '
        '${visible.isNotEmpty}.';

    if (local?.deletedAt != null && visible.isEmpty) {
      return ScenarioOutcome.pass(evidence);
    }
    return ScenarioOutcome.fail(
      'The todo was deleted on the server, but this device never hears about '
      'it and keeps showing it: the pull did not deliver the tombstone. '
      '$evidence',
    );
  } finally {
    engine.dispose();
    client.close();
  }
}

// ---------------------------------------------------------------------------
// P1
// ---------------------------------------------------------------------------

const _outboxIndexes = [
  'idx_sync_outbox_kind_entity',
  'idx_sync_outbox_kind_ts',
  'idx_sync_outbox_ts',
];

Future<ScenarioOutcome> _outboxQueriesAreIndexed(ScenarioContext ctx) async {
  final probe = _StatementProbe();
  final db = AppDatabase.open(name: _probeDatabase, interceptor: probe);
  final client = RecordingClient(maxRequests: 40);
  final engine = SyncEngine<AppDatabase>(
    db: db,
    transport: _transport(ctx, client),
    tables: [todoSyncTable(db)],
  );

  try {
    await _wipe(db);
    // A database as versions before the indexes created it.
    for (final index in _outboxIndexes) {
      await db.customStatement('DROP INDEX IF EXISTS $index');
    }
    await engine.sync();
    final indexes = await _indexesOf(db);

    final base = DateTime.utc(2026).microsecondsSinceEpoch;
    await db.batch(
      (b) => b.insertAll(db.syncOutbox, [
        for (var i = 0; i < _queuedOps; i++)
          SyncOutboxCompanion.insert(
            opId: 'probe-$i',
            kind: i.isEven ? _kind : 'notes',
            entityId: 'entity-${i % (_queuedOps ~/ 3)}',
            op: 'upsert',
            ts: 1700000000000 + i * 37 % 100000,
            payload: Value(jsonEncode({'id': 'entity-$i', 'title': 'x' * 300})),
            baseUpdatedAt: Value(base),
          ),
      ]),
    );

    probe.statements.clear();
    const runs = 20;
    final take = Stopwatch()..start();
    for (var i = 0; i < runs; i++) {
      await db.takeOutbox(limit: 100, kinds: {_kind}, maxTryCountExclusive: 5);
    }
    take.stop();
    final takeAll = Stopwatch()..start();
    for (var i = 0; i < runs; i++) {
      await db.takeOutbox(limit: 100, maxTryCountExclusive: 5);
    }
    takeAll.stop();
    final rebase = Stopwatch()..start();
    for (var i = 0; i < runs; i++) {
      await db.rebaseOutboxOps(
        kind: _kind,
        entityId: 'entity-${i * 2}',
        serverVersion: DateTime.utc(2026, 1, 2),
      );
    }
    rebase.stop();

    // The plans of the statements the library really sent.
    final issued = {
      for (final (statement, args) in probe.statements)
        if (statement.contains('sync_outbox')) statement: args,
    };
    final unindexed = <String>[];
    for (final MapEntry(key: statement, value: args) in issued.entries) {
      final plan = await _planOf(db, statement, args);
      final scans = plan.any(
        (step) =>
            step.contains('TEMP B-TREE') ||
            (step.contains('sync_outbox') && !step.contains('INDEX')),
      );
      if (scans) unindexed.add('${statement.split(' WHERE ').first}: $plan');
    }

    String ms(Stopwatch watch) =>
        (watch.elapsedMicroseconds / runs / 1000).toStringAsFixed(2);
    final evidence =
        'Indexes after the first sync: '
        '${indexes.isEmpty ? 'none' : indexes.join(', ')}. With $_queuedOps '
        'operations queued (average of $runs runs): take 100 of one kind '
        '${ms(take)} ms, take 100 of any kind ${ms(takeAll)} ms, re-base one '
        'entity ${ms(rebase)} ms. ${issued.length} distinct outbox '
        'statement(s) checked, ${unindexed.length} without an index.';

    if (indexes.length == _outboxIndexes.length && unindexed.isEmpty) {
      return ScenarioOutcome.pass(evidence);
    }
    return ScenarioOutcome.fail(
      'The queue is scanned (and sorted) for every batch and for every '
      'pushed operation, so draining N operations costs N². $evidence '
      '${unindexed.join(' | ')}',
    );
  } finally {
    engine.dispose();
    client.close();
    await _wipe(db);
    await db.close();
  }
}

// ---------------------------------------------------------------------------
// P3
// ---------------------------------------------------------------------------

Future<ScenarioOutcome> _batchIsCommittedOnce(ScenarioContext ctx) async {
  final probe = _StatementProbe();
  final db = AppDatabase.open(name: _probeDatabase, interceptor: probe);
  final client = RecordingClient(maxRequests: 200);
  final engine = SyncEngine<AppDatabase>(
    db: db,
    transport: _transport(ctx, client),
    tables: [todoSyncTable(db)],
  );
  final writer = SyncWriter<AppDatabase>(db).forTable(todoSyncTable(db));

  try {
    await _wipe(db);
    // The first sync of a database is a full resync; get it out of the way.
    await engine.sync();

    final now = DateTime.now().toUtc();
    for (var i = 0; i < _batchOps; i++) {
      await writer.insertAndEnqueue(
        Todo(id: 'scenario-${_uuid.v4()}', title: 'Batch $i', updatedAt: now),
        localTimestamp: now,
      );
    }

    probe.reset();
    final stopwatch = Stopwatch()..start();
    final stats = await engine.sync(pushKinds: {_kind}, pullKinds: const {});
    stopwatch.stop();

    final commits = probe.transactions + probe.writesOutsideTransaction;
    final evidence =
        'Pushed ${stats.pushed} operations in one batch in '
        '${stopwatch.elapsedMilliseconds} ms. Local commits while doing so: '
        '$commits (${probe.transactions} transaction(s), '
        '${probe.writesOutsideTransaction} write(s) committed on their own); '
        'operations left in the outbox: ${(await db.takeOutbox()).length}.';

    if (stats.pushed == _batchOps && commits <= 2) {
      return ScenarioOutcome.pass(evidence);
    }
    return ScenarioOutcome.fail(
      'Every server row, the acknowledgement and every re-base was '
      'committed separately: slow on disk, and a crash in between leaves '
      'rows written back whose operations are still queued. $evidence',
    );
  } finally {
    engine.dispose();
    client.close();
    await _wipe(db);
    await db.close();
  }
}

/// A second scratch database, opened with a [_StatementProbe].
const _probeDatabase = 'todo_advanced_scenarios_probe';

/// Sees every statement sent to the database it is attached to.
class _StatementProbe extends QueryInterceptor {
  final List<(String, List<Object?>)> statements = [];
  int transactions = 0;
  int writesOutsideTransaction = 0;

  void reset() {
    statements.clear();
    transactions = 0;
    writesOutsideTransaction = 0;
  }

  void _see(QueryExecutor executor, String statement, List<Object?> args) {
    statements.add((statement, args));
    final isWrite = !statement.trimLeft().toUpperCase().startsWith('SELECT');
    if (isWrite && executor is! TransactionExecutor) {
      writesOutsideTransaction++;
    }
  }

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    // Nested transactions are savepoints of the outer one, not commits.
    if (parent is! TransactionExecutor) transactions++;
    return super.beginTransaction(parent);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _see(executor, statement, args);
    return super.runSelect(executor, statement, args);
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _see(executor, statement, args);
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _see(executor, statement, args);
    return super.runUpdate(executor, statement, args);
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _see(executor, statement, args);
    return super.runDelete(executor, statement, args);
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _see(executor, statement, args);
    return super.runCustom(executor, statement, args);
  }
}

Future<List<String>> _indexesOf(AppDatabase db) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'index' "
        "AND tbl_name = 'sync_outbox' AND name LIKE 'idx_%' ORDER BY name",
      )
      .get();
  return [for (final row in rows) row.read<String>('name')];
}

Future<List<String>> _planOf(
  AppDatabase db,
  String statement,
  List<Object?> args,
) async {
  final rows = await db
      .customSelect(
        'EXPLAIN QUERY PLAN $statement',
        variables: [for (final arg in args) Variable<Object>(arg!)],
      )
      .get();
  return [for (final row in rows) row.read<String>('detail')];
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

/// Arms one of the backend's `POST /simulate/<what>` switches.
Future<void> _simulate(
  ScenarioContext ctx,
  String what,
  Map<String, Object?> body,
) async {
  final response = await http.post(
    Uri.parse('${ctx.backendUrl}/simulate/$what'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode(body),
  );
  if (response.statusCode != 200) {
    throw StateError(
      'simulate/$what failed: ${response.statusCode} ${response.body}',
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
