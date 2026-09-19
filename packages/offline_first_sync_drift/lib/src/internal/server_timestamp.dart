/// Parses a timestamp received from a server into UTC.
///
/// Accepts a [DateTime] or anything whose `toString()` is an ISO-8601 string.
/// A string **without** a zone designator (`2024-01-01T10:00:00`, common with
/// naive SQL drivers) is read as UTC. `DateTime.parse` would read it as the
/// device's local time, shifting it by the UTC offset — west of UTC that moves
/// a pull cursor into the future and rows in the gap are skipped.
///
/// Throws a [FormatException] when the value cannot be parsed.
DateTime parseServerTimestamp(Object value) {
  if (value is DateTime) return value.isUtc ? value : value.toUtc();

  final parsed = DateTime.parse(value.toString());
  // `DateTime.parse` yields a UTC value whenever the string carried `Z` or an
  // explicit offset; only zone-less input comes back as local time.
  if (parsed.isUtc) return parsed;

  return DateTime.utc(
    parsed.year,
    parsed.month,
    parsed.day,
    parsed.hour,
    parsed.minute,
    parsed.second,
    parsed.millisecond,
    parsed.microsecond,
  );
}
