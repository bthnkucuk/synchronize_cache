import 'dart:convert';

import 'package:test/test.dart';
import 'package:search_engine/src/content/json_text_content_parser.dart';

void main() {
  group('JsonTextContentParser', () {
    test('returns empty string for empty body', () async {
      const parser = JsonTextContentParser();
      expect(await parser.parse(body: ''), isEmpty);
    });

    test('extracts the default `text` field from a JSON object', () async {
      const parser = JsonTextContentParser();
      final body = jsonEncode({'text': 'hello world'});
      expect(await parser.parse(body: body), equals('hello world'));
    });

    test('honours a custom textKey', () async {
      const parser = JsonTextContentParser(textKey: 'body');
      final body = jsonEncode({'body': 'custom field', 'text': 'ignored'});
      expect(await parser.parse(body: body), equals('custom field'));
    });

    test('returns empty string when the field is missing', () async {
      const parser = JsonTextContentParser();
      final body = jsonEncode({'other': 'x'});
      expect(await parser.parse(body: body), isEmpty);
    });

    test('returns empty string when JSON is malformed', () async {
      const parser = JsonTextContentParser();
      expect(await parser.parse(body: '{not json'), isEmpty);
    });

    test('returns empty string when the decoded payload is not a Map', () async {
      const parser = JsonTextContentParser();
      expect(await parser.parse(body: '[1,2,3]'), isEmpty);
      expect(await parser.parse(body: '"plain string"'), isEmpty);
    });

    test('falls back to empty string when the field is null', () async {
      const parser = JsonTextContentParser();
      final body = jsonEncode({'text': null});
      expect(await parser.parse(body: body), isEmpty);
    });

    test('uses the injected jsonDecoder when provided', () async {
      var calls = 0;
      final parser = JsonTextContentParser(
        jsonDecoder: (body) async {
          calls++;
          return jsonDecode(body);
        },
      );
      final body = jsonEncode({'text': 'via worker'});
      expect(await parser.parse(body: body), equals('via worker'));
      expect(calls, equals(1));
    });

    test('decoder throwing is swallowed into empty string', () async {
      final parser = JsonTextContentParser(
        jsonDecoder: (_) async => throw Exception('boom'),
      );
      expect(await parser.parse(body: '{"text":"x"}'), isEmpty);
    });

    test('hint argument is accepted and ignored', () async {
      const parser = JsonTextContentParser();
      final body = jsonEncode({'text': 'still works'});
      expect(
        await parser.parse(body: body, hint: 'application/json'),
        equals('still works'),
      );
    });
  });
}
