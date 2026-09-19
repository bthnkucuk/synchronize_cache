/// Structural equality for JSON-like values: maps (regardless of key order),
/// lists (in order) and scalars.
///
/// `Map` and `List` compare by identity with `==`, so two separately decoded
/// but equal payloads need this to be recognised as equal.
bool deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return a == b;

  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!deepEquals(a[key], b[key])) return false;
    }
    return true;
  }

  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!deepEquals(a[i], b[i])) return false;
    }
    return true;
  }

  // Special-case doubles: NaN == NaN must report true for change detection.
  // IEEE 754 says NaN != NaN, but for diffing purposes two NaN values
  // represent the same "missing/invalid number" state, so we treat them
  // as equal. Without this, `identical(a, b)` at the top can return either
  // true or false for two NaN doubles depending on whether the VM happened
  // to canonicalize them, making diffMaps non-deterministic for NaN fields.
  if (a is double && b is double) {
    if (a.isNaN && b.isNaN) return true;
    return a == b;
  }

  return a == b;
}
