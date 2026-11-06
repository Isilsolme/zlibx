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

  /// Key for the get-books endpoint: the second-to-last segment of the
  /// list href (`/booklist/{id}/{hash}/{slug}.html` -> `{hash}`).
  /// The numeric [id] does NOT work there — the server answers
  /// "Requested page not found" (verified on device 2026-11-07).
  final String booksKey;

  const Booklist({
    required this.id,
    required this.name,
    this.description = '',
    this.author = '',
    this.count,
    this.views = '',
    this.coverUrl = '',
    required this.url,
    this.booksKey = '',
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
    // The live page carries the numeric id directly on the element
    // (id="4088695"), and its href uses the SINGULAR /booklist/{id}/...
    // shape. The old code only looked for a 'booklists' segment in the
    // href, so every real list was dropped and the screen showed "no
    // booklists" even when the page loaded fine (verified against the
    // live /booklists/my HTML 2026-11-06).
    final idAttr = el.attributes['id']?.trim();
    final id = (idAttr != null && RegExp(r'^\d+$').hasMatch(idAttr))
        ? idAttr
        : _idFromHref(href);
    if (id == null) return null;
    // The get-books endpoint is keyed by the href's second-to-last
    // segment (the hash), not the numeric id — see [Booklist.booksKey].
    final hrefSegments = Uri.tryParse(href)?.pathSegments ?? const <String>[];
    final booksKey =
        hrefSegments.length >= 3 ? hrefSegments[hrefSegments.length - 2] : '';
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
      booksKey: booksKey,
    );
  }

  /// The list id is the path segment after `/booklists/` — or the live
  /// site's singular `/booklist/` (`/booklist/4088695/...` -> `4088695`).
  static String? _idFromHref(String href) {
    if (href.isEmpty) return null;
    final segments = Uri.tryParse(href)?.pathSegments ?? const <String>[];
    var at = segments.indexOf('booklists');
    if (at < 0) at = segments.indexOf('booklist');
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
