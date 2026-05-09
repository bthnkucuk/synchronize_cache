/// Resolves a remote URL into a raw body string.
///
/// Pulled out of `SearchableTable.toGlobalSearch` so the same loader can be
/// reused across kinds, swapped for a different cache backend, or stubbed in
/// tests without touching the binding.
abstract interface class SearchContentLoader {
  Future<String> load(String url);
}
