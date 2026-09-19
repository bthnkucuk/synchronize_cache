import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';

/// How notes settle a conflict: by themselves, without asking anybody.
///
/// Todos use [ConflictStrategy.manual] and stop to ask. Notes take the
/// field-preserving merge — you changed the title here, the other device
/// changed the body, both survive — so the two kinds demonstrate the two
/// ends of the range in one app.
///
/// ### Why this is a resolver and not `ConflictStrategy.autoPreserve`
///
/// `autoPreserve` always answers with `AcceptMerged`, and the engine
/// silently drops `AcceptMerged` for anything that is not an upsert
/// (`conflict_service.dart`: `if (op is! UpsertOp) return null;`). A queued
/// *delete* that meets a server-side edit would therefore never resolve: the
/// operation stays in the outbox, is retried by every sync, and never counts
/// as stuck because conflicts do not touch the retry budget.
///
/// So notes run the same merge through the manual hook, where a delete can
/// be answered with something the engine acts on.
Future<ConflictResolution> resolveNoteConflict(
  Conflict conflict, {
  required void Function(String message) log,
}) async {
  // A queued delete has no payload; that empty map is the only signal the
  // resolver gets, because `Conflict` does not carry the operation type.
  if (conflict.localData.isEmpty) {
    final title = conflict.serverData['title'];
    log(
      'Note "$title" was edited on another device while you deleted it here '
      '— the edit wins and the note comes back. Delete it again if you '
      'still want it gone.',
    );
    // An edit beats a delete. It is the only automatic answer that destroys
    // nothing: the note reappears with the other device's text, and deleting
    // it a second time is one tap. The other way round, the other device's
    // work would be gone with no trace.
    return const AcceptServer();
  }

  final merged = ConflictUtils.preservingMerge(
    conflict.localData,
    conflict.serverData,
    changedFields: conflict.changedFields,
  );

  log(
    'Note "${merged.data['title']}" merged automatically — '
    '${_fields('this device', merged.localFields)}, '
    '${_fields('the other device', merged.serverFields)}.',
  );

  return AcceptMerged(
    merged.data,
    mergeInfo: MergeInfo(
      localFields: merged.localFields,
      serverFields: merged.serverFields,
    ),
  );
}

String _fields(String who, Set<String> fields) =>
    fields.isEmpty ? 'nothing from $who' : '${fields.join(', ')} from $who';
