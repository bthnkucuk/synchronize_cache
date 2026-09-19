// The outbox must carry the version an op was based on exactly as the app
// supplied it: servers compare `_baseUpdatedAt` with their `updated_at` for
// equality, so any precision loss turns into a spurious conflict.
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';
import 'package:test/test.dart';

import '../fixtures/test_database.dart';

/// `baseUpdatedAt` lives on the two concrete op types, not on [Op].
DateTime? baseOf(Op op) => switch (op) {
  UpsertOp(:final baseUpdatedAt) => baseUpdatedAt,
  DeleteOp(:final baseUpdatedAt) => baseUpdatedAt,
};

void main() {
  late TestDatabase db;

  setUp(() => db = TestDatabase());
  tearDown(() => db.close());

  UpsertOp upsert(
    String opId,
    String id, {
    DateTime? base,
    DateTime? at,
    String kind = 'test_item',
  }) => UpsertOp(
    opId: opId,
    kind: kind,
    id: id,
    localTimestamp: at ?? DateTime.utc(2026, 4, 1, 10),
    baseUpdatedAt: base,
    payloadJson: {'id': id, 'name': opId},
  );

  group('base version precision', () {
    final precise = DateTime.utc(2026, 4, 1, 10, 0, 0, 123, 456);

    test('an upsert keeps the microseconds of its base version', () async {
      await db.enqueue(upsert('op-1', 'a', base: precise));

      final op = (await db.takeOutbox()).single as UpsertOp;
      expect(op.baseUpdatedAt, precise);
      expect(op.baseUpdatedAt!.isUtc, isTrue);
    });

    test('a delete keeps the microseconds of its base version', () async {
      await db.enqueue(
        DeleteOp(
          opId: 'op-1',
          kind: 'test_item',
          id: 'a',
          localTimestamp: DateTime.utc(2026, 4, 1, 10),
          baseUpdatedAt: precise,
        ),
      );

      expect(baseOf((await db.takeOutbox()).single), precise);
    });

    test('a non-UTC base is stored as the same instant', () async {
      await db.enqueue(upsert('op-1', 'a', base: precise.toLocal()));

      final stored = baseOf((await db.takeOutbox()).single)!;
      expect(stored.isAtSameMomentAs(precise), isTrue);
    });

    test('rows written by older versions (milliseconds) still decode', () async {
      final legacy = DateTime.utc(2026, 4, 1, 10, 0, 0, 123);
      await db.customStatement(
        'INSERT INTO sync_outbox '
        '(op_id, kind, entity_id, op, payload, ts, try_count, base_updated_at) '
        "VALUES ('legacy', 'test_item', 'a', 'upsert', '{}', ?, 0, ?)",
        [legacy.millisecondsSinceEpoch, legacy.millisecondsSinceEpoch],
      );

      expect(baseOf((await db.takeOutbox()).single), legacy);
    });

    test('a null base stays null', () async {
      await db.enqueue(upsert('op-1', 'a'));

      expect(baseOf((await db.takeOutbox()).single), isNull);
    });
  });

  group('rebaseOutboxOps', () {
    final oldVersion = DateTime.utc(2026, 4, 1, 10);
    final newVersion = DateTime.utc(2026, 4, 1, 10, 0, 5, 678, 901);

    test('re-bases every queued op of that entity, and only those', () async {
      await db.enqueue(upsert('a-1', 'a', base: oldVersion));
      await db.enqueue(upsert('a-2', 'a', base: oldVersion));
      await db.enqueue(upsert('b-1', 'b', base: oldVersion));
      await db.enqueue(
        upsert('other-kind', 'a', base: oldVersion, kind: 'other_kind'),
      );

      final changed = await db.rebaseOutboxOps(
        kind: 'test_item',
        entityId: 'a',
        serverVersion: newVersion,
      );

      expect(changed, 2);
      final bases = {
        for (final op in await db.takeOutbox()) op.opId: baseOf(op),
      };
      expect(bases, {
        'a-1': newVersion,
        'a-2': newVersion,
        'b-1': oldVersion,
        'other-kind': oldVersion,
      });
    });

    test('never invents a base for an op that has none', () async {
      // A null base means "create, fail if it exists" to the server.
      await db.enqueue(upsert('create', 'a'));
      await db.enqueue(upsert('edit', 'a', base: oldVersion));

      await db.rebaseOutboxOps(
        kind: 'test_item',
        entityId: 'a',
        serverVersion: newVersion,
      );

      final bases = {
        for (final op in await db.takeOutbox()) op.opId: baseOf(op),
      };
      expect(bases, {'create': null, 'edit': newVersion});
    });
  });

  group('outbox order', () {
    test(
      'ops enqueued within the same millisecond keep insertion order',
      () async {
        // `ORDER BY ts` alone leaves ties unordered; two edits of one entity
        // in the same millisecond could be pushed newest-first.
        final at = DateTime.utc(2026, 4, 1, 10);
        for (final opId in ['op-c', 'op-a', 'op-d', 'op-b']) {
          await db.enqueue(upsert(opId, 'a', at: at));
        }

        final order = (await db.takeOutbox()).map((op) => op.opId).toList();
        expect(order, ['op-c', 'op-a', 'op-d', 'op-b']);
      },
    );
  });
}
