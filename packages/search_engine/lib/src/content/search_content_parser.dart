// ignore_for_file: comment_references

/// Converts a raw body into the plain text that should land in the FTS5
/// `content` column. Implementations are format-specific (JSON, markdown,
/// PDF, …) and stateless — same instance can be shared across bindings.
///
/// [hint] is a free-form context channel — typically a mime-type or path
/// suffix the binding already knows. Implementations may ignore it.
// ignore: one_member_abstracts
abstract interface class SearchContentParser {
  Future<String> parse({required String body, String? hint});
}
