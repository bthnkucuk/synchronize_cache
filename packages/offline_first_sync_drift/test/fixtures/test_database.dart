import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';

import 'test_database.drift.dart';

export 'test_database.drift.dart';

// Мок транспорта
class MockTransport implements TransportAdapter {
  final List<Map<String, dynamic>> pullResponses = [];
  final List<Op> pushedOps = [];
  bool healthStatus = true;
  int pullCallCount = 0;
  int pushCallCount = 0;
  String? lastAfterId;

  @override
  Future<PullPage> pull({
    required String kind,
    required DateTime updatedSince,
    required int pageSize,
    String? pageToken,
    String? afterId,
    bool includeDeleted = true,
  }) async {
    pullCallCount++;
    lastAfterId = afterId;
    return PullPage(items: pullResponses);
  }

  @override
  Future<BatchPushResult> push(List<Op> ops) async {
    pushCallCount++;
    pushedOps.addAll(ops);
    return BatchPushResult(
      results:
          ops
              .map(
                (op) =>
                    OpPushResult(opId: op.opId, result: const PushSuccess()),
              )
              .toList(),
    );
  }

  @override
  Future<PushResult> forcePush(Op op) async {
    pushedOps.add(op);
    return const PushSuccess();
  }

  @override
  Future<FetchResult> fetch({required String kind, required String id}) async =>
      const FetchNotFound();

  @override
  Future<bool> health() async => healthStatus;
}

// Тестовая модель
class TestItem {
  TestItem({
    required this.id,
    required this.updatedAt,
    this.deletedAt,
    this.deletedAtLocal,
    required this.name,
  });

  final String id;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final DateTime? deletedAtLocal;
  final String name;

  factory TestItem.fromJson(Map<String, dynamic> json) => TestItem(
    id: json['id'] as String,
    updatedAt: DateTime.parse(json['updated_at'] as String),
    deletedAt:
        json['deleted_at'] != null
            ? DateTime.parse(json['deleted_at'] as String)
            : null,
    name: json['name'] as String,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
    'name': name,
  };
}

// Тестовая таблица
@UseRowClass(TestItem, generateInsertable: true)
class TestItems extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get name => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  include: {'package:offline_first_sync_drift/src/sync_tables.drift'},
  tables: [TestItems],
)
class TestDatabase extends $TestDatabase with SyncDatabaseMixin {
  TestDatabase() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;
}
