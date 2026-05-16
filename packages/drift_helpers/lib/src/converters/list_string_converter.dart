// converters/string_list_converter.dart
import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:developer';
import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

/// TypeConverter for text[] columns
/// Stores list of strings as JSON text in SQLite
@immutable
final class StringListConverter extends TypeConverter<List<String>, String>
    with JsonTypeConverter2<List<String>, String, Object?> {
  const StringListConverter();

  /// Eğer ayrı bir json/text sütunu (Postgres) için ihtiyaç olursa:
  static JsonTypeConverter2<List<String>, String, Object?> jsonConverter = TypeConverter.json2(
    fromJson: (json) => (json! as List).map((e) => e.toString()).toList(),
    toJson: (value) => value,
  );

  // ---------- SQL <-> Dart ----------
  @override
  List<String> fromSql(String fromDb) {
    if (fromDb.isEmpty) return const [];
    try {
      final decoded = jsonDecode(fromDb);
      return decoded is List ? decoded.map((e) => e.toString()).toList() : const [];
    } catch (e, st) {
      log('StringListConverter catch block: $e\n$st');
      return const [];
    }
  }

  @override
  String toSql(List<String> value) => jsonEncode(value);

  // ---------- JSON <-> Dart ----------
  @override
  List<String> fromJson(Object? json) {
    if (json == null) return const [];
    if (json is List) return json.map((e) => e.toString()).toList();
    // Tek bir string gelirse daima listeye sar
    return [json.toString()];
  }

  @override
  Object toJson(List<String> value) => value;
}
