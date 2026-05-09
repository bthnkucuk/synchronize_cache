import 'package:equatable/equatable.dart';

/// Value object representing a row in the `pending_search_items` table.
///
/// `data` is the decoded JSON payload that the per-kind parser will turn
/// into a [GlobalSearch] when the engine flushes the queue. Persisted as
/// a JSON-encoded string in the `string_data` column.
class PendingSearchItem extends Equatable {
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

  @override
  List<Object?> get props => [userId, kind, id, deleted, data];
}
