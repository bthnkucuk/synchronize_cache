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
  });
}
