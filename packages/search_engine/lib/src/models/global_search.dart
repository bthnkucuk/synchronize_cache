import 'package:drift/drift.dart';
import 'package:equatable/equatable.dart';

/// Domain row representation of a hit in the FTS5 `global_search` virtual
/// table.
///
/// Each searchable field exists in two forms:
/// - **raw** (`title` / `description` / `content`) — what the user typed,
///   surfaced unchanged via `highlight()` / `snippet()`.
/// - **normalized** (`titleNormalized` / `descriptionNormalized` /
///   `contentNormalized`) — diacritic-stripped + lowercased, indexed for
///   `MATCH`. Fed by `SearchEngine`'s injected `normalizer` callback.
///
/// User queries are normalized the same way before being sent to FTS5, so
/// `şehir`-flavoured rows remain searchable as `sehir` without losing the
/// original glyphs in the highlight output.
class GlobalSearch extends Equatable {
  const GlobalSearch({
    required this.originalId,
    required this.userId,
    required this.kind,
    required this.title,
    required this.description,
    required this.content,
    this.titleNormalized = '',
    this.descriptionNormalized = '',
    this.contentNormalized = '',
    this.hlTitle,
    this.hlDescription,
    this.hlContent,
  });

  factory GlobalSearch.fromJson(Map<String, dynamic> json) {
    return GlobalSearch(
      originalId: json['original_id'] as String,
      userId: json['user_id'] as String,
      kind: json['kind'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      content: json['content'] as String,
      titleNormalized: (json['title_normalized'] as String?) ?? '',
      descriptionNormalized: (json['description_normalized'] as String?) ?? '',
      contentNormalized: (json['content_normalized'] as String?) ?? '',
    );
  }

  factory GlobalSearch.fromSql(QueryRow row) {
    return GlobalSearch(
      originalId: row.read<String>('original_id'),
      userId: row.read<String>('user_id'),
      kind: row.read<String>('kind'),
      title: row.read<String>('title'),
      description: row.read<String>('description'),
      content: row.read<String>('content'),
      titleNormalized: row.readNullable<String>('title_normalized') ?? '',
      descriptionNormalized: row.readNullable<String>('description_normalized') ?? '',
      contentNormalized: row.readNullable<String>('content_normalized') ?? '',
      hlTitle: row.read<String>('hl_title'),
      hlDescription: row.read<String>('hl_desc'),
      hlContent: row.read<String>('hl_content'),
    );
  }

  final String originalId;
  final String userId;
  final String kind;
  final String title;
  final String description;
  final String content;

  /// Diacritic-stripped + lowercased `title`, used by FTS5 `MATCH`.
  final String titleNormalized;

  /// Diacritic-stripped + lowercased `description`, used by FTS5 `MATCH`.
  final String descriptionNormalized;

  /// Diacritic-stripped + lowercased `content`, used by FTS5 `MATCH`.
  final String contentNormalized;

  final String? hlTitle;
  final String? hlDescription;
  final String? hlContent;

  /// Returns a copy with the three normalized fields filled by [normalizer]
  /// applied to the raw fields. No-op when [normalizer] is `null`.
  GlobalSearch normalize(String Function(String)? normalizer) {
    if (normalizer == null) return this;
    return GlobalSearch(
      originalId: originalId,
      userId: userId,
      kind: kind,
      title: title,
      description: description,
      content: content,
      titleNormalized: normalizer(title),
      descriptionNormalized: normalizer(description),
      contentNormalized: normalizer(content),
      hlTitle: hlTitle,
      hlDescription: hlDescription,
      hlContent: hlContent,
    );
  }

  String get displayedTitle => hlTitle ?? title;

  String get displayedDescription {
    final nHlDesc = hlDescription ?? '';
    final nHlContent = hlContent ?? '';
    final nDescription = description;
    if (nHlDesc.isNotEmpty) {
      return nHlDesc;
    }
    if (nHlContent.isNotEmpty) {
      return nHlContent;
    }
    return nDescription;
  }

  Map<String, dynamic> toJson() {
    return {
      'original_id': originalId,
      'user_id': userId,
      'kind': kind,
      'title': title,
      'description': description,
      'content': content,
      'title_normalized': titleNormalized,
      'description_normalized': descriptionNormalized,
      'content_normalized': contentNormalized,
    };
  }

  @override
  List<Object?> get props => [
        originalId,
        userId,
        kind,
        title,
        description,
        content,
        titleNormalized,
        descriptionNormalized,
        contentNormalized,
        hlTitle,
        hlDescription,
        hlContent,
      ];
}
