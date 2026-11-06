import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'book.dart';

/// One Z-Library booklist (the website's "booklists" feature: a named,
/// shareable collection of books with an author and a book count).
///
/// Read-only v1: browsing public booklists, the signed-in user's own
/// booklists, and the books inside one booklist. Creating a booklist or
/// adding books to one is NOT wired — those write endpoints have not
/// been confirmed yet.
class Booklist {
  /// The numeric id from the list URL (`/booklists/{id}/...`).
  final String id;

  /// List name (`topic` attribute on the list element).
  final String name;
  final String description;

  /// The creator's username (`authorprofile` attribute), or ''.
  final String author;

  /// Book count (`quantity` attribute), null when the page did not say.
  final int? count;

  /// View count (`views` attribute), or ''.
  final String views;

  /// Cover thumbnail (first carousel image's `data-src`), or ''.
  final String coverUrl;

  /// Absolute URL of the list page on the mirror.
  final String url;

  const Booklist({
    required this.id,
    required this.name,
    this.description = '',
    this.author = '',
    this.count,
    this.views = '',
    this.coverUrl = '',
    required this.url,
  });

  /// Build from one `<z-booklist>` element of a `/booklists` (or
  /// `/booklists/my`) list page. Attribute shapes follow the public
  /// sertraline/zlibrary client (read as a shape reference only — no
  /// code copied): `topic` = name, `href` = list URL, `description`,
  /// `authorprofile`, `quantity`, `views`; the cover is the first
  /// carousel image's `data-src`. Returns null when the element has no
  /// usable name or id.
  static Booklist? fromElement(dom.Element el, {required String baseUrl}) {
    final name = el.attributes['topic']?.trim();
    if (name == null || name.isEmpty) return null;
    final href = el.attributes['href']?.trim() ?? '';
    final id = _idFromHref(href);
    if (id == null) return null;
    var coverUrl = '';
    for (final img in el.querySelectorAll('img')) {
      final src = img.attributes['data-src']?.trim() ?? '';
      if (src.isNotEmpty) {
        coverUrl = _resolveUrl(src, baseUrl);
        break;
      }
    }
    return Booklist(
      id: id,
      name: name,
      description: el.attributes['description']?.trim() ?? '',
      author: el.attributes['authorprofile']?.trim() ?? '',
      count: int.tryParse(el.attributes['quantity']?.trim() ?? ''),
      views: el.attributes['views']?.trim() ?? '',
      coverUrl: coverUrl,
      url: _resolveUrl(href, baseUrl),
    );
  }

  /// The list id is the path segment after `/booklists/`
  /// (`/booklists/12345/slug` -> `12345`).
  static String? _idFromHref(String href) {
    if (href.isEmpty) return null;
    final segments = Uri.tryParse(href)?.pathSegments ?? const <String>[];
    final at = segments.indexOf('booklists');
    if (at < 0 || at + 1 >= segments.length) return null;
    final id = segments[at + 1];
    return id.isEmpty ? null : id;
  }

  static String _resolveUrl(String raw, String baseUrl) {
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }
    if (raw.startsWith('//')) return 'https:$raw';
    if (raw.startsWith('/')) return '$baseUrl$raw';
    return raw;
  }
}

/// One page of booklist search results.
///
/// [totalPages] is 0 when the page did not carry a page count — callers
/// then page until an empty page arrives.
class BooklistsPage {
  final List<Booklist> lists;
  final int totalPages;

  const BooklistsPage({required this.lists, this.totalPages = 0});
}

/// Books inside one booklist, from
/// `GET /papi/booklist/{id}/get-books/{page}`.
class BooklistBooksPage {
  final List<Book> books;
  final int totalPages;

  const BooklistBooksPage({required this.books, this.totalPages = 1});
}

/// Parse a `/booklists` (or `/booklists/my`) list page (HTML) into a
/// [BooklistsPage]. A page with no `<z-booklist>` elements parses to an
/// empty list (covers both "nothing found" and past-the-end pages).
/// The page count lives in an inline script
/// (`var pagerOptions = {... pagesTotal: N, ...}`); absent means unknown.
BooklistsPage parseBooklistsPage(String html, {required String baseUrl}) {
  final doc = html_parser.parse(html);
  final lists = doc
      .querySelectorAll('z-booklist')
      .map((el) => Booklist.fromElement(el, baseUrl: baseUrl))
      .whereType<Booklist>()
      .toList();
  var totalPages = 0;
  final match = RegExp(r'pagesTotal:\s*(\d+)').firstMatch(html);
  if (match != null) totalPages = int.tryParse(match.group(1)!) ?? 0;
  return BooklistsPage(lists: lists, totalPages: totalPages);
}
