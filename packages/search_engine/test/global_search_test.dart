import 'package:test/test.dart';
import 'package:search_engine/src/models/global_search.dart';

/// Builds a fresh, non-const instance. Identical `const` instances are
/// canonicalized by Dart, which would let `==` pass on identity alone and
/// hide a broken value-equality implementation.
GlobalSearch _gs({
  String originalId = 'o',
  String userId = 'u',
  String kind = 'k',
  String title = 't',
  String description = 'd',
  String content = 'c',
  String titleNormalized = 'tn',
  String descriptionNormalized = 'dn',
  String contentNormalized = 'cn',
  String? hlTitle = 'ht',
  String? hlDescription = 'hd',
  String? hlContent = 'hc',
}) => GlobalSearch(
  originalId: originalId,
  userId: userId,
  kind: kind,
  title: title,
  description: description,
  content: content,
  titleNormalized: titleNormalized,
  descriptionNormalized: descriptionNormalized,
  contentNormalized: contentNormalized,
  hlTitle: hlTitle,
  hlDescription: hlDescription,
  hlContent: hlContent,
);

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

    test(
      'displayedDescription prefers hlDesc then hlContent then description',
      () {
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
      },
    );

    test('every field participates in equality, highlights included', () {
      final base = _gs();
      final variants = <String, GlobalSearch>{
        'originalId': _gs(originalId: 'other'),
        'userId': _gs(userId: 'other'),
        'kind': _gs(kind: 'other'),
        'title': _gs(title: 'other'),
        'description': _gs(description: 'other'),
        'content': _gs(content: 'other'),
        'titleNormalized': _gs(titleNormalized: 'other'),
        'descriptionNormalized': _gs(descriptionNormalized: 'other'),
        'contentNormalized': _gs(contentNormalized: 'other'),
        'hlTitle': _gs(hlTitle: 'other'),
        'hlDescription': _gs(hlDescription: 'other'),
        'hlContent': _gs(hlContent: 'other'),
        'hlTitle (null)': _gs(hlTitle: null),
        'hlDescription (null)': _gs(hlDescription: null),
        'hlContent (null)': _gs(hlContent: null),
      };
      for (final MapEntry(key: field, value: variant) in variants.entries) {
        expect(variant, isNot(equals(base)), reason: '$field must matter');
      }
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

      expect(
        gs.toJson(),
        equals({
          'original_id': 'o',
          'user_id': 'u',
          'kind': 'k',
          'title': 'T',
          'description': 'D',
          'content': 'C',
          'title_normalized': 't',
          'description_normalized': 'd',
          'content_normalized': 'c',
        }),
      );
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

    test(
      'normalize fills the *_normalized fields by applying the callback',
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
        expect(
          normalized.title,
          equals('Şehir'),
          reason: 'normalize must not mutate raw fields',
        );
      },
    );

    test('normalize overwrites *_normalized fields cleanly when they were '
        'already populated', () {
      const original = GlobalSearch(
        originalId: 'o',
        userId: 'u',
        kind: 'k',
        title: 'Şehir',
        description: 'Tğürk',
        content: 'İçerik',
        // Pre-populated with stale normalized values that bear no relation
        // to the raw fields — normalize must overwrite them.
        titleNormalized: 'STALE',
        descriptionNormalized: 'STALE',
        contentNormalized: 'STALE',
      );

      String stripDiacritics(String s) => s
          .replaceAll('Ş', 's')
          .replaceAll('ğ', 'g')
          .replaceAll('ü', 'u')
          .replaceAll('İ', 'i')
          .replaceAll('ç', 'c')
          .toLowerCase();

      final out = original.normalize(stripDiacritics);
      expect(out.titleNormalized, equals('sehir'));
      expect(out.descriptionNormalized, equals('tgurk'));
      expect(out.contentNormalized, equals('icerik'));
      // Original instance untouched (it's immutable).
      expect(original.titleNormalized, equals('STALE'));
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

    test(
      'displayedTitle falls back to raw title when no highlight is present',
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
      },
    );

    test('equality is value based, not identity based', () {
      final a = _gs();
      final b = _gs();
      expect(identical(a, b), isFalse, reason: 'test must not be vacuous');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('instances decoded from the same JSON are equal', () {
      final json = _gs().toJson();
      final a = GlobalSearch.fromJson(json);
      final b = GlobalSearch.fromJson(json);
      expect(identical(a, b), isFalse);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('works as a Set element / Map key', () {
      final set = {_gs(), _gs(), _gs(originalId: 'other')};
      expect(set, hasLength(2));
    });

    test('is never equal to an unrelated object', () {
      expect(_gs(), isNot(equals('o')));
    });

    test('toString lists the fields', () {
      final text = _gs().toString();
      expect(text, startsWith('GlobalSearch('));
      expect(text, contains('originalId: o'));
      expect(text, contains('hlContent: hc'));
    });
  });
}
