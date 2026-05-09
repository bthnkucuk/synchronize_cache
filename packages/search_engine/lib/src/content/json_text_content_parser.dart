import 'dart:async';
import 'dart:convert';

import 'package:search_engine/src/content/search_content_parser.dart';

/// [SearchContentParser] that decodes [body] as JSON and returns the value
/// at [textKey] (default `text`). Returns the empty string when the body
/// is empty, malformed, or the field is missing — search indexing should
/// keep going even when a single row's content cannot be extracted.
///
/// [jsonDecoder] is optional; when provided it runs the decode step
/// (typically off-isolate via a worker pool). Defaults to `dart:convert`'s
/// in-line `jsonDecode`.
class JsonTextContentParser implements SearchContentParser {
  const JsonTextContentParser({this.jsonDecoder, this.textKey = 'text'});

  final FutureOr<dynamic> Function(String body)? jsonDecoder;
  final String textKey;

  @override
  Future<String> parse({required String body, String? hint}) async {
    if (body.isEmpty) return '';
    try {
      final decoded = jsonDecoder != null ? await jsonDecoder!(body) : jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return (decoded[textKey] as String?) ?? '';
      }
    } catch (_) {
      // fall through
    }
    return '';
  }
}
