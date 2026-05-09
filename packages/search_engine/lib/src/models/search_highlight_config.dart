/// Configures the open/close tags wrapped around matched terms by FTS5
/// `highlight()` / `snippet()` and the snippet ellipsis + token budget.
///
/// Pass [SearchHighlightConfig.none] to opt out of any wrapping (returns
/// raw text in the highlight columns).
class SearchHighlightConfig {
  const SearchHighlightConfig({
    this.titleOpen = '<span class="h-title">',
    this.titleClose = '</span>',
    this.descOpen = '<span class="h-desc">',
    this.descClose = '</span>',
    this.contentOpen = '<span class="h-content">',
    this.contentClose = '</span>',
    this.snippetEllipsis = '...',
    this.snippetTokenCount = 64,
  });

  final String titleOpen;
  final String titleClose;
  final String descOpen;
  final String descClose;
  final String contentOpen;
  final String contentClose;
  final String snippetEllipsis;

  /// FTS5 `snippet()` accepts a token count in the inclusive range
  /// `[-64, 64]`; values outside the range raise `snippet number of tokens
  /// out of range` at query time. Default is `64` (the maximum).
  final int snippetTokenCount;

  /// No-op highlight wrapping — useful when the consumer wants the raw
  /// matched text without any markup.
  static const SearchHighlightConfig none = SearchHighlightConfig(
    titleOpen: '',
    titleClose: '',
    descOpen: '',
    descClose: '',
    contentOpen: '',
    contentClose: '',
  );
}
