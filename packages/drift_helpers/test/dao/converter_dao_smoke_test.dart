// Integration smoke test for drift_helpers' TypeConverters.
//
// `drift_helpers` is pure-Dart and exports a handful of `TypeConverter`
// subclasses (JsonConverter, JsonListConverter, IntListConverter,
// StringListConverter). The Flutter Test Strategy in the ire monorepo
// (where this package was forked from) calls for a `NativeDatabase.memory()`
// DAO smoke test to catch converter API drift cheaply.
//
// `drift_helpers` itself declares no `@DriftDatabase` (only converters), so
// a full DAO+migration test would need to live elsewhere. The next-best
// thing — and what this test does — is to pin every converter against a
// live in-memory sqlite3 engine using the same pure-Dart bindings drift
// uses under the hood (`package:sqlite3`, which is what `drift/native.dart`'s
// `NativeDatabase` wraps). For each converter we:
//
//   1. Call `toSql(value)` and write the result through a real INSERT.
//   2. Read the value back with a SELECT.
//   3. Feed the raw string to `fromSql` and assert equality with the input.
//
// Catches:
//   - Inheritance / signature changes in drift's `TypeConverter`.
//   - SQL <-> Dart serialization regressions (e.g. an `fromSql` that starts
//     throwing instead of returning a sentinel).
//   - `null` vs empty-string handling drift at the SQL boundary.
//
// Pure-Dart: `package:test/test.dart` (NOT `flutter_test`) and the pure-Dart
// `sqlite3` package (NOT `sqlite3_flutter_libs`).

import 'package:drift_helpers/drift_helpers.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  late Database db;

  setUp(() {
    db =
        sqlite3.openInMemory()
          ..execute('CREATE TABLE blob_text (v TEXT)')
          ..execute('CREATE TABLE blob_text_nullable (v TEXT)');
  });

  tearDown(() {
    db.dispose();
  });

  void write(String table, Object? sqlValue) {
    db.execute('DELETE FROM $table');
    final stmt = db.prepare('INSERT INTO $table (v) VALUES (?)');
    try {
      stmt.execute([sqlValue]);
    } finally {
      stmt.dispose();
    }
  }

  String? read(String table) {
    final rs = db.select('SELECT v FROM $table');
    expect(rs, hasLength(1));
    return rs.single['v'] as String?;
  }

  group('JsonConverter (sqlite3 in-memory round-trip)', () {
    const converter = JsonConverter();

    test('round-trips a populated map', () {
      final value = <String, dynamic>{'k': 'v', 'n': 42, 'b': true};

      write('blob_text_nullable', converter.toSql(value));
      final raw = read('blob_text_nullable');

      expect(converter.fromSql(raw), equals(value));
    });

    test('null in -> "{}" out -> empty map on read', () {
      // JsonConverter.toSql(null) returns "{}" (empty object). The read path
      // then sees a non-null, non-empty string and yields an empty map.
      write('blob_text_nullable', converter.toSql(null));
      final raw = read('blob_text_nullable');

      expect(raw, '{}');
      expect(converter.fromSql(raw), equals(<String, dynamic>{}));
    });

    test('explicit SQL NULL round-trips to Dart null', () {
      write('blob_text_nullable', null);
      final raw = read('blob_text_nullable');

      expect(raw, isNull);
      expect(converter.fromSql(raw), isNull);
    });
  });

  group('JsonListConverter (sqlite3 in-memory round-trip)', () {
    const converter = JsonListConverter();

    test('round-trips a list of maps', () {
      final value = <Map<String, dynamic>>[
        {'i': 1},
        {'i': 2, 'label': 'two'},
      ];

      write('blob_text_nullable', converter.toSql(value));
      final raw = read('blob_text_nullable');

      expect(converter.fromSql(raw), equals(value));
    });

    test('null round-trips as null', () {
      write('blob_text_nullable', converter.toSql(null));
      final raw = read('blob_text_nullable');

      expect(raw, isNull);
      expect(converter.fromSql(raw), isNull);
    });
  });

  group('IntListConverter (sqlite3 in-memory round-trip)', () {
    const converter = IntListConverter();

    test('round-trips a list of ints', () {
      final value = <int>[1, 2, 3];

      write('blob_text', converter.toSql(value));
      final raw = read('blob_text');

      expect(raw, isNotNull);
      expect(converter.fromSql(raw!), equals(value));
    });

    test('empty list round-trips as empty', () {
      write('blob_text', converter.toSql(const []));
      final raw = read('blob_text');

      expect(raw, '[]');
      expect(converter.fromSql(raw!), isEmpty);
    });
  });

  group('StringListConverter (sqlite3 in-memory round-trip)', () {
    const converter = StringListConverter();

    test('round-trips a list of strings', () {
      final value = <String>['alpha', 'beta', 'gamma'];

      write('blob_text', converter.toSql(value));
      final raw = read('blob_text');

      expect(raw, isNotNull);
      expect(converter.fromSql(raw!), equals(value));
    });

    test('empty list round-trips as empty', () {
      write('blob_text', converter.toSql(const []));
      final raw = read('blob_text');

      expect(raw, '[]');
      expect(converter.fromSql(raw!), isEmpty);
    });
  });
}
