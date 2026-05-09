import 'package:test/test.dart';
import 'package:search_engine/src/models/search_highlight_config.dart';

void main() {
  group('SearchHighlightConfig', () {
    test('defaults wrap raw text with span markup', () {
      const cfg = SearchHighlightConfig();
      expect(cfg.titleOpen, equals('<span class="h-title">'));
      expect(cfg.titleClose, equals('</span>'));
      expect(cfg.descOpen, equals('<span class="h-desc">'));
      expect(cfg.descClose, equals('</span>'));
      expect(cfg.contentOpen, equals('<span class="h-content">'));
      expect(cfg.contentClose, equals('</span>'));
      expect(cfg.snippetEllipsis, equals('...'));
      expect(cfg.snippetTokenCount, equals(64));
    });

    test('custom values are stored verbatim', () {
      const cfg = SearchHighlightConfig(
        titleOpen: '<b>',
        titleClose: '</b>',
        descOpen: '<i>',
        descClose: '</i>',
        contentOpen: '<u>',
        contentClose: '</u>',
        snippetEllipsis: '…',
        snippetTokenCount: 16,
      );
      expect(cfg.titleOpen, equals('<b>'));
      expect(cfg.titleClose, equals('</b>'));
      expect(cfg.descOpen, equals('<i>'));
      expect(cfg.descClose, equals('</i>'));
      expect(cfg.contentOpen, equals('<u>'));
      expect(cfg.contentClose, equals('</u>'));
      expect(cfg.snippetEllipsis, equals('…'));
      expect(cfg.snippetTokenCount, equals(16));
    });

    test('SearchHighlightConfig.none strips every wrapper', () {
      const cfg = SearchHighlightConfig.none;
      expect(cfg.titleOpen, isEmpty);
      expect(cfg.titleClose, isEmpty);
      expect(cfg.descOpen, isEmpty);
      expect(cfg.descClose, isEmpty);
      expect(cfg.contentOpen, isEmpty);
      expect(cfg.contentClose, isEmpty);
      // ellipsis + token count keep their defaults
      expect(cfg.snippetEllipsis, equals('...'));
      expect(cfg.snippetTokenCount, equals(64));
    });
  });
}
