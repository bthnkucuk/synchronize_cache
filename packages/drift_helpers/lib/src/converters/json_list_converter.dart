import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:developer';
import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

/// TypeConverter for jsonb arrays whose elements are objects.
/// Stores `List<Map<String, dynamic>>?` as JSON text in SQLite.
@immutable
final class JsonListConverter extends TypeConverter<List<Map<String, dynamic>>?, String?>
    with JsonTypeConverter2<List<Map<String, dynamic>>?, String?, Object?> {
  const JsonListConverter();

  @override
  List<Map<String, dynamic>>? fromSql(String? fromDb) {
    if (fromDb == null || fromDb.isEmpty) return null;
    try {
      final decoded = jsonDecode(fromDb);
      if (decoded is! List) return null;
      return decoded.whereType<Map>().map(Map<String, dynamic>.from).toList();
    } catch (e, st) {
      log('JsonListConverter catch block: $e\n$st');
      return null;
    }
  }

  @override
  String? toSql(List<Map<String, dynamic>>? value) {
    if (value == null) return null;
    return jsonEncode(value);
  }

  @override
  List<Map<String, dynamic>>? fromJson(Object? json) {
    if (json == null) return null;
    if (json is List) {
      return json.whereType<Map>().map(Map<String, dynamic>.from).toList();
    }
    return null;
  }

  @override
  Object? toJson(List<Map<String, dynamic>>? value) => value;
}
