import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:developer';
import 'package:drift/drift.dart';

/// TypeConverter for JSON/jsonb columns
/// Stores JSON as text in SQLite and handles JSON serialization/deserialization
class JsonConverter extends TypeConverter<Map<String, dynamic>?, String?>
    with JsonTypeConverter2<Map<String, dynamic>?, String?, Object?> {
  const JsonConverter();

  // ---------- SQL <-> Dart ----------
  @override
  Map<String, dynamic>? fromSql(String? fromDb) {
    if (fromDb == null || fromDb.isEmpty) return null;
    try {
      final decoded = jsonDecode(fromDb);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (e, st) {
      log('JsonConverter catch block: $e\n$st');
      return null;
    }
  }

  @override
  String toSql(Map<String, dynamic>? value) {
    if (value == null) return '{}';
    return jsonEncode(value);
  }

  // ---------- JSON <-> Dart ----------
  @override
  Map<String, dynamic>? fromJson(Object? json) {
    if (json == null) return null;
    if (json is Map) return Map<String, dynamic>.from(json);
    return null;
  }

  @override
  Object? toJson(Map<String, dynamic>? value) => value;
}
