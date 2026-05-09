import 'package:test/test.dart';
import 'package:search_engine/src/models/global_search.dart';

void main() {
  group('GlobalSearch', () {
    test('fromJson and toJson roundtrip', () {
      const gs = GlobalSearch(
        originalId: 'o',
        userId: 'u',
        kind: 'k',
        title: 't',
        description: 'd',
        content: 'c',
      );
      final json = gs.toJson();
      final parsed = GlobalSearch.fromJson(json);
      expect(parsed.originalId, equals('o'));
      expect(parsed.title, equals('t'));
    });

    test('displayedTitle prefers highlight', () {
      const gs = GlobalSearch(
        originalId: 'o',
        userId: 'u',
        kind: 'k',
        title: 'plain',
        description: 'd',
        content: 'c',
        hlTitle: '<span>h</span>',
      );
      expect(gs.displayedTitle, equals('<span>h</span>'));
    });

    test('displayedDescription prefers hlDesc then hlContent then description', () {
      const onlyDesc = GlobalSearch(
        originalId: 'o',
        userId: 'u',
        kind: 'k',
        title: 't',
        description: 'base',
        content: 'c',
      );
      expect(onlyDesc.displayedDescription, equals('base'));

      const hlContent = GlobalSearch(
        originalId: 'o',
        userId: 'u',
        kind: 'k',
        title: 't',
        description: 'base',
        content: 'c',
        hlContent: 'hlC',
      );
      expect(hlContent.displayedDescription, equals('hlC'));

      const hlDesc = GlobalSearch(
        originalId: 'o',
        userId: 'u',
        kind: 'k',
        title: 't',
        description: 'base',
        content: 'c',
        hlDescription: 'hlD',
        hlContent: 'hlC',
      );
      expect(hlDesc.displayedDescription, equals('hlD'));
    });

    test('props includes highlight fields', () {
      const a = GlobalSearch(
        originalId: 'o',
        userId: 'u',
        kind: 'k',
        title: 't',
        description: 'd',
        content: 'c',
        hlTitle: 'h1',
      );
      const b = GlobalSearch(
        originalId: 'o',
        userId: 'u',
        kind: 'k',
        title: 't',
        description: 'd',
        content: 'c',
        hlTitle: 'h2',
      );
      expect(a, isNot(equals(b)));
    });

    test('toJson exposes raw + normalized columns', () {
      const gs = GlobalSearch(
        originalId: 'o',
        userId: 'u',
        kind: 'k',
        title: 'T',
        description: 'D',
        content: 'C',
        titleNormalized: 't',
        descriptionNormalized: 'd',
        contentNormalized: 'c',
      );

      expect(gs.toJson(), equals({
        'original_id': 'o',
        'user_id': 'u',
        'kind': 'k',
        'title': 'T',
        'description': 'D',
        'content': 'C',
        'title_normalized': 't',
        'description_normalized': 'd',
        'content_normalized': 'c',
      }));
    });

    test('fromJson defaults missing normalized columns to empty strings', () {
      final gs = GlobalSearch.fromJson(const {
        'original_id': 'o',
        'user_id': 'u',
        'kind': 'k',
        'title': 'T',
        'description': 'D',
        'content': 'C',
      });

      expect(gs.titleNormalized, isEmpty);
      expect(gs.descriptionNormalized, isEmpty);
      expect(gs.contentNormalized, isEmpty);
    });

    test('normalize fills the *_normalized fields by applying the callback',
        () {
      const original = GlobalSearch(
        originalId: 'o',
        userId: 'u',
        kind: 'k',
        title: 'Şehir',
        description: 'Tğürk',
        content: 'İçerik',
      );

      String stripDiacritics(String s) => s
          .replaceAll('Ş', 's')
          .replaceAll('ğ', 'g')
          .replaceAll('ü', 'u')
          .replaceAll('İ', 'i')
          .replaceAll('ç', 'c')
          .toLowerCase();

      final normalized = original.normalize(stripDiacritics);

      expect(normalized.titleNormalized, equals('sehir'));
      expect(normalized.descriptionNormalized, equals('tgurk'));
      expect(normalized.contentNormalized, equals('icerik'));
      expect(normalized.title, equals('Şehir'),
          reason: 'normalize must not mutate raw fields');
    });

    test('normalize is a no-op when the normalizer is null', () {
      const gs = GlobalSearch(
        originalId: 'o',
        userId: 'u',
        kind: 'k',
        title: 't',
        description: 'd',
        content: 'c',
      );
      final out = gs.normalize(null);
      expect(out, same(gs));
    });

    test('normalize preserves highlight fields', () {
      const gs = GlobalSearch(
        originalId: 'o',
        userId: 'u',
        kind: 'k',
        title: 'T',
        description: 'D',
        content: 'C',
        hlTitle: 'hT',
        hlDescription: 'hD',
        hlContent: 'hC',
      );
      final out = gs.normalize((s) => s.toLowerCase());
      expect(out.hlTitle, equals('hT'));
      expect(out.hlDescription, equals('hD'));
      expect(out.hlContent, equals('hC'));
    });

    test('displayedTitle falls back to raw title when no highlight is present',
        () {
      const gs = GlobalSearch(
        originalId: 'o',
        userId: 'u',
        kind: 'k',
        title: 'plain title',
        description: 'd',
        content: 'c',
      );
      expect(gs.displayedTitle, equals('plain title'));
    });

    test('equal instances are equatable + hashable', () {
      const a = GlobalSearch(
        originalId: 'o',
        userId: 'u',
        kind: 'k',
        title: 't',
        description: 'd',
        content: 'c',
      );
      const b = GlobalSearch(
        originalId: 'o',
        userId: 'u',
        kind: 'k',
        title: 't',
        description: 'd',
        content: 'c',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
