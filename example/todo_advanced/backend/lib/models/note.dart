import 'package:json_annotation/json_annotation.dart';
import 'package:todo_advanced_backend/models/sync_record.dart';

part 'note.g.dart';

/// Note model for the backend — the example's second synced kind.
///
/// Notes exist so the app can show that a single sync engine carries more
/// than one table, and that each kind can use its own conflict strategy
/// (todos ask the user, notes merge automatically).
///
/// Uses snake_case for JSON serialization.
@JsonSerializable(fieldRename: FieldRename.snake)
class Note implements SyncRecord {
  Note({
    required this.id,
    required this.title,
    this.body,
    this.pinned = false,
    required this.updatedAt,
    this.deletedAt,
  });

  factory Note.fromJson(Map<String, dynamic> json) => _$NoteFromJson(json);

  @override
  final String id;
  final String title;
  final String? body;
  final bool pinned;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;

  @override
  Map<String, dynamic> toJson() => _$NoteToJson(this);

  Note copyWith({
    String? id,
    String? title,
    String? body,
    bool? pinned,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      pinned: pinned ?? this.pinned,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}
