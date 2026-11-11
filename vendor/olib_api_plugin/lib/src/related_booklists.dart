import 'package:html/parser.dart' as html_parser;

import 'book_detail_html.dart';
import 'booklist.dart';

/// Everything one book detail page carries beyond the eapi book
/// object, parsed from a single `GET /book/{hash}/{slug}.html` fetch:
/// the server-rendered metadata rows plus the related-booklists
/// block. `fetchBookDetailExtras` (in the search mixin) returns this,
/// so the detail page costs ONE HTML fetch for both.
class BookDetailExtras {
  /// The `bookProperty` rows (volume / ISBN / IPFS / rating — see
  /// [parseBookDetailProperties]). May be all-null when the page has
  /// no property box.
  final BookDetailMetadata metadata;

  /// The booklists the site shows under 关联书单 ("related booklists")
  /// at the bottom of the detail page. Empty when the page carries no
  /// block (most books have none — the capture shows one that does).
  final List<Booklist> relatedBooklists;

  const BookDetailExtras({
    required this.metadata,
    required this.relatedBooklists,
  });
}

/// The related booklists of one book detail page, from the
/// server-rendered `div.related-booklists-block` section.
///
/// Shape confirmed from the live capture 2026-11-12 (Firefox,
/// zh.z-library.sk, the 超速学习 book page): the block holds a
/// `div.z-booklists-carousel` (attributes `data-book_id` /
/// `data-loader="loadBooklists"` / `data-booklists_type="related"`)
/// whose `<z-booklist>` cards are ALREADY RENDERED — the loader
/// attributes drive the site's lazy top-up for scrolling, not the
/// initial content, so the cards parse straight from the page and no
/// AJAX endpoint is needed for v1. Each card:
///
///     <z-booklist tile="" href="/booklist/498889/f77552/1.html"
///                id="498889" topic="1" quantity="32">
///       <z-cover id="5748099" author="木暮太一" title="…" priority="true">
///         <img data-src="https://…jpg"></z-cover>
///       <z-cover …>…</z-cover>   ← the list's books, stacked
///     </z-booklist>
///
/// `topic` is the list's display name and may be a bare number
/// (`topic="1"` on the first captured card) or a word (`学习`) — both
/// pass through as [Booklist.name]. The card carries no
/// author/views/color attributes; those `Booklist` fields stay empty.
/// The per-book hash is NOT on the covers here (the site's booklist
/// page wraps each cover in a link to `/book/{hash}/…`; the related
/// block does not), so [Booklist.previewBooks] parse with `hash`
/// null — they are display-only previews.
List<Booklist> parseRelatedBooklists(String html, {required String baseUrl}) {
  final doc = html_parser.parse(html);
  final block = doc.querySelector('.related-booklists-block');
  if (block == null) return const [];
  return block
      .querySelectorAll('z-booklist')
      .map((el) => Booklist.fromElement(el, baseUrl: baseUrl))
      .whereType<Booklist>()
      .toList();
}
