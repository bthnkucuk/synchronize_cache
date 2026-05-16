import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:developer';
import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

/// TypeConverter for integer[] columns
/// Stores list of ints as JSON text in SQLite.
@immutable
final class IntListConverter extends TypeConverter<List<int>, String> with JsonTypeConverter2<List<int>, String, Object?> {
  const IntListConverter();

  @override
  List<int> fromSql(String fromDb) {
    if (fromDb.isEmpty) return const [];
    try {
      final decoded = jsonDecode(fromDb);
      return decoded is List ? decoded.map((e) => (e as num).toInt()).toList() : const [];
    } catch (e, st) {
      log('IntListConverter catch block: $e\n$st');
      return const [];
    }
  }

  @override
  String toSql(List<int> value) => jsonEncode(value);

  @override
  List<int> fromJson(Object? json) {
    if (json == null) return const [];
    if (json is List) return json.map((e) => (e as num).toInt()).toList();
    return const [];
  }

  @override
  Object toJson(List<int> value) => value;
}
