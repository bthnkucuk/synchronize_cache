// The pull cursor is the lower bound of the next pull. It was stored in
// milliseconds; against a server with microsecond versions it therefore
// pointed just BEFORE the last row it had seen, and every later pull got that
// row (and everything else within the same millisecond) delivered again.
import 'package:drift/drift.dart' show Variable;
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';
import 'package:offline_first_sync_drift/src/internal/timestamp_codec.dart';
import 'package:test/test.dart';

import '../fixtures/test_database.dart';

const _kind = 'test_item';

/// Serves rows the way docs/backend-transport.md specifies:
/// `updated_at > since OR (updated_at == since AND id > afterId)`.
class _KeysetServer implements TransportAdapter {
  _KeysetServer(this.rows);

  final List<Map<String, Object?>> rows;
  final List<DateTime> requestedSince = [];

  @override
  Future<PullPage> pull({
    required String kind,
    required DateTime updatedSince,
    required int pageSize,
    String? pageToken,
    String? afterId,
    bool includeDeleted = true,
  }) async {
    requestedSince.add(updatedSince);
    final since = updatedSince.toUtc();
    final items = rows.where((row) {
      final updatedAt = DateTime.parse(row['updated_at']! as String);
      return updatedAt.isAfter(since) ||
          (updatedAt.isAtSameMomentAs(since) &&
              (row['id']! as String).compareTo(afterId ?? '') > 0);
    }).toList();
    return PullPage(items: items);
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

void main() {
  late TestDatabase db;

  setUp(() => db = TestDatabase());
  tearDown(() => db.close());

  group('sync_cursors.ts', () {
    test('keeps the microseconds of the server version', () async {
      final version = DateTime.utc(2026, 5, 1, 12, 0, 0, 123, 456);

      await db.setCursor(_kind, Cursor(ts: version, lastId: 'z'));

      final cursor = await db.getCursor(_kind);
      expect(cursor!.ts, version);
      expect(cursor.lastId, 'z');
    });

    test(
      'a cursor written in milliseconds by an older version is still read',
      () async {
        final version = DateTime.utc(2026, 5, 1, 12, 0, 0, 123);
        await db.customStatement(
          'INSERT INTO sync_cursors (kind, ts, last_id) VALUES (?, ?, ?)',
          [_kind, version.millisecondsSinceEpoch, 'z'],
        );

        expect((await db.getCursor(_kind))!.ts, version);
      },
    );

    test('the reset cursor is still the epoch', () async {
      await CursorService(db).reset(_kind);

      final cursor = await db.getCursor(_kind);
      expect(cursor!.ts, DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
    });

    test('the last full resync keeps working', () async {
      final at = DateTime.utc(2026, 5, 1, 12, 0, 0, 1, 2);

      await CursorService(db).setLastFullResync(at);

      expect(await CursorService(db).getLastFullResync(), at);
    });
  });

  test('a second pull does not get the last row delivered again', () async {
    final server = _KeysetServer([
      {'id': 'a', 'name': 'first', 'updated_at': '2026-05-01T12:00:00.123111Z'},
      {'id': 'b', 'name': 'last', 'updated_at': '2026-05-01T12:00:00.123456Z'},
    ]);
    final engine = SyncEngine<TestDatabase>(
      db: db,
      transport: server,
      tables: [
        SyncableTable<TestItem>(
          kind: _kind,
          table: db.testItems,
          fromJson: TestItem.fromJson,
          toJson: (e) => e.toJson(),
          toInsertable: (e) => e.toInsertable(),
          getId: (e) => e.id,
          getUpdatedAt: (e) => e.updatedAt,
        ),
      ],
    );
    addTearDown(engine.dispose);

    final first = await engine.sync();
    final second = await engine.sync();
    final third = await engine.sync();

    expect(first.pulled, 2);
    expect(second.pulled, 0, reason: 'nothing changed on the server');
    expect(third.pulled, 0);
    expect(
      server.requestedSince.last,
      DateTime.utc(2026, 5, 1, 12, 0, 0, 123, 456),
    );
  });

  group('timestamp codec', () {
    final dates = [
      DateTime.utc(2026, 5, 1, 12, 0, 0, 123, 456),
      DateTime.utc(2026, 5, 1, 12),
      DateTime.utc(1973, 3, 3, 9, 46, 40), // 1e14 µs exactly
      DateTime.utc(2255, 1, 1, 0, 0, 0, 0, 1),
      DateTime.utc(1960, 1, 1, 0, 0, 0, 5, 7),
    ];
    for (final date in dates) {
      test('round-trips $date', () {
        expect(decodeTimestamp(encodeTimestamp(date)), date);
      });
    }

    // Read back as milliseconds, so stored as milliseconds: never a value
    // that decodes to another moment (an `updated_at` defaulted to the epoch
    // used to come back as a date far in the future).
    for (final date in [
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      DateTime.utc(1970, 1, 1, 0, 0, 5),
      DateTime.utc(1971, 8, 1, 10, 30),
      DateTime.utc(1968, 2, 29),
    ]) {
      test('round-trips $date, from the years 1e14 µs cannot tell apart', () {
        expect(decodeTimestamp(encodeTimestamp(date)), date);
      });
    }

    test('reads milliseconds written by older versions', () {
      final date = DateTime.utc(2024, 6, 1, 8, 30, 0, 250);
      expect(decodeTimestamp(date.millisecondsSinceEpoch), date);
    });
  });

  test('an outbox base from before 1973 survives the outbox', () async {
    final base = DateTime.utc(1970, 1, 1, 0, 0, 5);
    await db.enqueue(
      UpsertOp(
        opId: 'op-1',
        kind: _kind,
        id: 'a',
        localTimestamp: DateTime.utc(2026),
        payloadJson: const {'id': 'a'},
        baseUpdatedAt: base,
      ),
    );

    final op = (await db.takeOutbox()).single as UpsertOp;
    expect(op.baseUpdatedAt, base);

    final stored = await db
        .customSelect(
          'SELECT base_updated_at AS b FROM sync_outbox WHERE op_id = ?',
          variables: [Variable.withString('op-1')],
        )
        .getSingle();
    expect(stored.read<int>('b'), base.millisecondsSinceEpoch);
  });
}
