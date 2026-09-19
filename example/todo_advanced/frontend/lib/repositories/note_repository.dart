import 'package:drift/drift.dart';
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';

/// Repository for managing notes with offline-first sync support.
///
/// Same three rules as `TodoRepository`: write locally first, enqueue the
/// operation, and always hand `replaceAndEnqueue` the version that was
/// edited (`baseUpdatedAt`) plus the fields that actually changed.
class NoteRepository {
  NoteRepository(this._db, SyncableTable<Note> syncTable)
    : _writer = SyncWriter<AppDatabase>(_db).forTable(syncTable);

  final AppDatabase _db;
  final _uuid = const Uuid();
  final SyncEntityWriter<Note, AppDatabase> _writer;

  /// Watches all non-deleted notes: pinned first, then newest first.
  Stream<List<Note>> watchAll() {
    return (_db.select(_db.notes)
          ..where((n) => n.deletedAt.isNull() & n.deletedAtLocal.isNull())
          ..orderBy([
            (n) => OrderingTerm(expression: n.pinned, mode: OrderingMode.desc),
            (n) =>
                OrderingTerm(expression: n.updatedAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  /// Gets all non-deleted notes.
  Future<List<Note>> getAll() {
    return (_db.select(
      _db.notes,
    )..where((n) => n.deletedAt.isNull() & n.deletedAtLocal.isNull())).get();
  }

  /// Gets a note by ID.
  Future<Note?> getById(String id) {
    return (_db.select(
      _db.notes,
    )..where((n) => n.id.equals(id))).getSingleOrNull();
  }

  /// Creates a new note and enqueues it for sync.
  Future<Note> create({
    required String title,
    String? body,
    bool pinned = false,
  }) async {
    final now = DateTime.now().toUtc();
    final note = Note(
      id: _uuid.v4(),
      title: title,
      body: body,
      pinned: pinned,
      updatedAt: now,
    );

    await _writer.insertAndEnqueue(note, localTimestamp: now);
    return note;
  }

  /// Updates an existing note.
  ///
  /// The changed fields are named in snake_case because they are matched
  /// against the JSON payload, not against the Dart field names.
  Future<Note> update(
    Note note, {
    String? title,
    String? body,
    bool? pinned,
  }) async {
    final now = DateTime.now().toUtc();
    final changedFields = <String>{};

    if (title != null && title != note.title) changedFields.add('title');
    if (body != note.body) changedFields.add('body');
    if (pinned != null && pinned != note.pinned) changedFields.add('pinned');

    final updated = Note(
      id: note.id,
      title: title ?? note.title,
      // `body` is passed through as given so clearing it really clears it.
      body: body,
      pinned: pinned ?? note.pinned,
      updatedAt: now,
      deletedAt: note.deletedAt,
      deletedAtLocal: note.deletedAtLocal,
    );

    await _writer.replaceAndEnqueue(
      updated,
      baseUpdatedAt: note.updatedAt,
      changedFields: changedFields.isNotEmpty ? changedFields : null,
      localTimestamp: now,
    );

    return updated;
  }

  /// Flips the pinned flag.
  Future<Note> togglePinned(Note note) =>
      update(note, body: note.body, pinned: !note.pinned);

  /// Deletes a note (soft delete locally, enqueue for sync).
  Future<void> delete(Note note) async {
    final now = DateTime.now().toUtc();
    // `updatedAt` moves too, even though the *base* version sent to the
    // server is still the one below: a server-side tombstone carries a new
    // `updated_at`, and anything derived from this table — the search index
    // above all — only notices a row whose version moved forward.
    final deleted = note.copyWith(deletedAtLocal: now, updatedAt: now);

    await _writer.writeAndEnqueueDelete(
      localWrite: () async {
        await _db.update(_db.notes).replace(deleted.toInsertable());
      },
      id: note.id,
      baseUpdatedAt: note.updatedAt,
      localTimestamp: now,
    );
  }
}
