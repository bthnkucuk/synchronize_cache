/// Value object representing a row in the `pending_search_items` table.
///
/// `data` is the decoded JSON payload that the per-kind parser will turn
/// into a [GlobalSearch] when the engine flushes the queue. Persisted as
/// a JSON-encoded string in the `string_data` column.
class PendingSearchItem {
  const PendingSearchItem({
    required this.userId,
    required this.kind,
    required this.id,
    required this.data,
    this.deleted = false,
  });

  final String userId;
  final String kind;
  final String id;
  final bool deleted;
  final Map<String, dynamic> data;

  /// Value equality. [data] is compared deeply, as decoded JSON: nested maps
  /// (regardless of key order) and lists (in order) are equal when their
  /// contents are.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PendingSearchItem &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          kind == other.kind &&
          id == other.id &&
          deleted == other.deleted &&
          _jsonEquals(data, other.data);

  @override
  int get hashCode =>
      Object.hash(runtimeType, userId, kind, id, deleted, _jsonHash(data));

  @override
  String toString() =>
      'PendingSearchItem(userId: $userId, kind: $kind, id: $id, '
      'deleted: $deleted, data: $data)';
}

/// Deep equality for decoded JSON: maps, lists and primitives.
bool _jsonEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map<Object?, Object?> && b is Map<Object?, Object?>) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_jsonEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List<Object?> && b is List<Object?>) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// Hash consistent with [_jsonEquals]. Map entries are combined with XOR so
/// the result does not depend on key order.
int _jsonHash(Object? value) {
  if (value is Map<Object?, Object?>) {
    var hash = value.length;
    for (final entry in value.entries) {
      hash ^= Object.hash(entry.key, _jsonHash(entry.value));
    }
    return hash;
  }
  if (value is List<Object?>) return Object.hashAll(value.map(_jsonHash));
  return value.hashCode;
}
