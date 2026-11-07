import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'book.dart';

/// One Z-Library booklist (the website's "booklists" feature: a named,
/// shareable collection of books with an author and a book count).
///
/// Browsing public booklists, the signed-in user's own booklists, and
/// the books inside one booklist, plus creating a booklist
/// (`ZLibraryApi.createBooklist`). Adding books to a list and deleting
/// lists are NOT wired — those write endpoints have not been captured.
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

  /// Books from the list page's own carousel (`<z-cover>` children:
  /// id, title, author, cover, hash from the wrapping link). The
  /// detail screen paints these instantly — no fetch — and only
  /// fetches the detail page when the carousel is short of the list
  /// total. Empty when the page carried no carousel (e.g. a list
  /// created through the API response parser).
  final List<Book> previewBooks;

  const Booklist({
    required this.id,
    required this.name,
    this.description = '',
    this.author = '',
    this.count,
    this.views = '',
    this.coverUrl = '',
    required this.url,
    this.previewBooks = const [],
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
    var coverUrl = '';
    for (final img in el.querySelectorAll('img')) {
      final src = img.attributes['data-src']?.trim() ?? '';
      if (src.isNotEmpty) {
        coverUrl = _resolveUrl(src, baseUrl);
        break;
      }
    }
    // The carousel already carries every book the list page shows:
    // each <z-cover> has the numeric id, title and author as
    // attributes, the cover in a child <img data-src>, and the book
    // hash in the wrapping <a href="/book/{hash}/..."> (verified
    // against the live /booklists/my HTML 2026-11-06 — the 001 card
    // carries all 5 of its books this way). The detail screen paints
    // these instantly instead of fetching the detail page.
    final previewBooks = <Book>[];
    for (final cover in el.querySelectorAll('z-cover')) {
      final bookId = int.tryParse(cover.attributes['id']?.trim() ?? '');
      if (bookId == null) continue;
      final img = cover.querySelector('img');
      final coverRaw = img?.attributes['data-src']?.trim() ??
          img?.attributes['src']?.trim() ??
          '';
      dom.Element? linkEl;
      var node = cover.parent;
      while (node != null) {
        if (node is dom.Element && node.localName == 'a') {
          linkEl = node;
          break;
        }
        node = node.parent;
      }
      previewBooks.add(
        Book(
          id: bookId,
          title: cover.attributes['title']?.trim() ?? '',
          hash: _hashFromBookHref(linkEl?.attributes['href'] ?? ''),
          author: _cardAttr(cover, 'author'),
          cover: coverRaw.isEmpty ? null : _resolveUrl(coverRaw, baseUrl),
        ),
      );
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
      previewBooks: previewBooks,
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

/// Books on the FIRST page of a booklist detail page, from the
/// server-rendered `<z-bookcard>` elements (`.readlist-view`).
///
/// Page 1 is never served by the JSON endpoint (see
/// `getBooklistBooks` in the API layer) — it lives in the detail document.
/// Shape confirmed from the live `/booklist/4088695/62a0c2/001.html`
/// document 2026-11-07: each card carries the book in its attributes
/// (`id`, `href`, `publisher`, `language`, `year`, `extension`,
/// `filesize`, `rating`, `read`), the cover in a child `<img
/// data-src>`, and the title/author in `<div slot="title">` /
/// `<div slot="author">`. The book hash is the first segment of the
/// href (`/book/{hash}/{slug}.html`). The `user_token` attribute (a
/// JWT carrying the signed-in user's identity) is deliberately NOT
/// read. Cards marked `deleted="1"` are skipped. An empty list means
/// the page had no cards (or was not a detail page at all).
List<Book> parseBooklistDetailBooks(String html, {String? baseUrl}) {
  final doc = html_parser.parse(html);
  final books = <Book>[];
  for (final card in doc.querySelectorAll('z-bookcard')) {
    final id = int.tryParse(card.attributes['id']?.trim() ?? '');
    if (id == null) continue;
    if (card.attributes['deleted']?.trim() == '1') continue;
    final href = card.attributes['href']?.trim() ?? '';
    final img = card.querySelector('img');
    final coverRaw = img?.attributes['data-src']?.trim() ??
        img?.attributes['src']?.trim() ??
        '';
    final title =
        card.querySelector('div[slot="title"]')?.text.trim() ?? '';
    final author =
        card.querySelector('div[slot="author"]')?.text.trim() ?? '';
    books.add(
      Book(
        id: id,
        title: title,
        hash: _hashFromBookHref(href),
        author: author.isEmpty ? null : author,
        cover: coverRaw.isEmpty
            ? null
            : (baseUrl == null ? coverRaw : _resolveCardUrl(coverRaw, baseUrl)),
        publisher: _cardAttr(card, 'publisher'),
        year: int.tryParse(card.attributes['year']?.trim() ?? ''),
        language: _cardAttr(card, 'language'),
        extension: _cardAttr(card, 'extension'),
        filesizeString: _cardAttr(card, 'filesize'),
        interestScore: _cardAttr(card, 'rating'),
        readOnlineUrl: _cardAttr(card, 'read'),
      ),
    );
  }
  return books;
}

String? _cardAttr(dom.Element el, String name) {
  final value = el.attributes[name]?.trim();
  return value == null || value.isEmpty ? null : value;
}

/// Book hash from a `/book/{hash}/{slug}.html` href, or null when the
/// href does not have that shape.
String? _hashFromBookHref(String href) {
  final segments = Uri.tryParse(href)?.pathSegments ?? const <String>[];
  if (segments.length >= 2 && segments[0] == 'book') {
    final hash = segments[1];
    return hash.isEmpty ? null : hash;
  }
  return null;
}

String _resolveCardUrl(String raw, String baseUrl) {
  if (raw.startsWith('http://') || raw.startsWith('https://')) {
    return raw;
  }
  if (raw.startsWith('//')) return 'https:$raw';
  if (raw.startsWith('/')) return '$baseUrl$raw';
  return raw;
}
