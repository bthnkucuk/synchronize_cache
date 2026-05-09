/// Server-managed fields that must never be sent in a PUT body.
///
/// The sync server strips any of these that appear in the push payload, but
/// removing them on the client keeps the wire size small and avoids
/// accidental attempts to overwrite server-controlled values.
const Set<String> serverManagedFields = {
  'id',
  'bundle_id',
  'user_id',
  'created_at',
  'updated_at',
  'deleted_at',
};

/// Returns a copy of [json] with all [serverManagedFields] removed.
///
/// Pass this to `SyncableTable.toJson` wrapping when you need to ensure a
/// push payload is clean before handing it to the transport layer.
Map<String, dynamic> stripServerManagedFields(Map<String, dynamic> json) {
  return {
    for (final entry in json.entries)
      if (!serverManagedFields.contains(entry.key)) entry.key: entry.value,
  };
}
