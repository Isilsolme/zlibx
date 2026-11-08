/// One book as returned by the Z-Library eapi.
///
/// Only `id` and `title` are required: the app itself constructs minimal
/// [Book] objects from download history with just `id`, `title`, `author`,
/// `cover` and `extension`. Every other field is nullable because list
/// responses omit fields that detail responses include (and vice versa).
///
/// `fromJson` accepts both camelCase and snake_case keys, and coerces
/// int/string mismatches, because the eapi is not formally documented and
/// different endpoints spell the same field differently.
class Book {
  final int id;
  final String title;
  final String? hash;
  final String? author;
  final String? cover;
  final String? description;
  final String? publisher;
  final int? year;
  final String? language;

  /// Website category, e.g. "Fiction - Horror" (eapi `categories`).
  /// Present only when the detail response carries it — not every book
  /// has one, so the detail page shows the chip only when non-empty.
  final String? categories;
  final int? pages;
  final String? series;
  final String? extension;

  /// Raw size in bytes, when the server (or the app, for LAN imports)
  /// provides it. [filesizeString] is the display form.
  final int? filesize;
  final String? filesizeString;
  final String? interestScore;
  final String? readOnlineUrl;

  const Book({
    required this.id,
    required this.title,
    this.hash,
    this.author,
    this.cover,
    this.description,
    this.publisher,
    this.year,
    this.language,
    this.categories,
    this.pages,
    this.series,
    this.extension,
    this.filesize,
    this.filesizeString,
    this.interestScore,
    this.readOnlineUrl,
  });

  factory Book.fromJson(Map<String, dynamic> json) {
    // The get-books JSON carries no `hash`, but its `href` does:
    // `/book/{hash}/{slug}.html`. The detail screen needs the hash
    // (`GET /eapi/book/{id}/{hash}`), so derive it when absent.
    final href = _asString(json['href']);
    return Book(
      id: _asInt(json['id']) ?? 0,
      title: _asString(json['title']) ?? '',
      // An EMPTY hash string must not shadow the href fallback below:
      // `hash: ""` would produce `/eapi/book/{id}/` requests that only
      // the expensive resolveEapiHash search could ever repair.
      hash: _nonEmptyString(json['hash'] ?? json['hashId']) ??
          _hashFromBookHref(href),
      author: _joinAuthor(json['author']),
      cover: _asString(json['cover']),
      description: _asString(json['description']),
      publisher: _asString(json['publisher']),
      year: _asInt(json['year']),
      language: _asString(json['language']),
      categories: _joinCategories(json['categories']),
      pages: _asInt(json['pages']),
      series: _asString(json['series']),
      extension: _asString(json['extension']),
      filesize: _asInt(json['filesize']),
      filesizeString: _filesizeString(json),
      interestScore: _asString(
        json['interestScore'] ??
            json['interest_score'] ??
            json['qualityScore'],
      ),
      readOnlineUrl: _asString(
        json['readOnlineUrl'] ?? json['read_online_url'],
      ),
    );
  }

  /// Book hash from a `/book/{hash}/{slug}.html` href, or null when the
  /// href does not have that shape.
  static String? _hashFromBookHref(String? href) {
    if (href == null || href.isEmpty) return null;
    final segments = Uri.tryParse(href)?.pathSegments ?? const <String>[];
    if (segments.length >= 2 && segments[0] == 'book') {
      final hash = segments[1];
      return hash.isEmpty ? null : hash;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    if (hash != null) 'hash': hash,
    if (author != null) 'author': author,
    if (cover != null) 'cover': cover,
    if (description != null) 'description': description,
    if (publisher != null) 'publisher': publisher,
    if (year != null) 'year': year,
    if (language != null) 'language': language,
    if (categories != null) 'categories': categories,
    if (pages != null) 'pages': pages,
    if (series != null) 'series': series,
    if (extension != null) 'extension': extension,
    if (filesize != null) 'filesize': filesize,
    if (filesizeString != null) 'filesizeString': filesizeString,
    if (interestScore != null) 'interestScore': interestScore,
    if (readOnlineUrl != null) 'readOnlineUrl': readOnlineUrl,
  };

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString());
  }

  static String? _asString(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    return v.toString();
  }

  static String? _joinAuthor(dynamic v) {
    if (v == null) return null;
    if (v is List) {
      return v.map((e) => e.toString()).where((e) => e.isNotEmpty).join(', ');
    }
    return _asString(v);
  }

  /// Categories arrive as one string ("Fiction - Horror") in the eapi
  /// detail response; a list form is joined the same way as authors.
  static String? _joinCategories(dynamic v) {
    if (v == null) return null;
    if (v is List) {
      final parts =
          v.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
      return parts.isEmpty ? null : parts.join(', ');
    }
    final text = _asString(v);
    return text == null || text.isEmpty ? null : text;
  }

  static String? _filesizeString(Map<String, dynamic> json) {
    final direct = _asString(
      json['filesizeString'] ?? json['filesize_string'],
    );
    if (direct != null) return direct;
    final bytes = _asInt(json['filesize']);
    if (bytes == null) return null;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// [_asString] with empty-string normalization: many endpoints return
  /// `""` instead of omitting optional fields, and an empty value must
  /// behave like an absent one.
  static String? _nonEmptyString(dynamic v) {
    final s = _asString(v);
    return (s == null || s.isEmpty) ? null : s;
  }
}
