import 'package:test/test.dart';
import 'package:search_engine/src/content/search_content_loader.dart';
import 'package:search_engine/src/content/search_content_parser.dart';

class _FakeLoader implements SearchContentLoader {
  _FakeLoader(this._payload);
  final Map<String, String> _payload;

  @override
  Future<String> load(String url) async {
    final value = _payload[url];
    if (value == null) throw StateError('no payload for $url');
    return value;
  }
}

class _UpperCaseParser implements SearchContentParser {
  @override
  Future<String> parse({required String body, String? hint}) async =>
      hint == null ? body.toUpperCase() : '$hint:${body.toUpperCase()}';
}

void main() {
  group('SearchContentLoader', () {
    test('implementations resolve URLs to bodies', () async {
      final loader = _FakeLoader({'/a': 'alpha', '/b': 'beta'});
      expect(await loader.load('/a'), equals('alpha'));
      expect(await loader.load('/b'), equals('beta'));
    });

    test('implementations propagate errors for unknown URLs', () async {
      final loader = _FakeLoader(const {});
      expect(loader.load('/missing'), throwsStateError);
    });
  });

  group('SearchContentParser', () {
    test('runs without a hint', () async {
      final parser = _UpperCaseParser();
      expect(await parser.parse(body: 'hello'), equals('HELLO'));
    });

    test('uses the hint when provided', () async {
      final parser = _UpperCaseParser();
      expect(
        await parser.parse(body: 'hello', hint: 'json'),
        equals('json:HELLO'),
      );
    });
  });
}
