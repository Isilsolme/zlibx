import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Metadata parsed from a book detail page's HTML
/// (`GET /book/{hash}/{slug}.html`).
///
/// The eapi book object does not carry these fields — they only exist
/// as server-rendered rows in the detail page, one row per property:
/// a `div.bookProperty.property_<key>` holding a
/// `div.property_label` (text ends with `:` or `：`) and a
/// `div.property_value` (plain text, sometimes with inner spans —
/// the text is taken). Rows are matched by the `property_<key>`
/// class (locale-independent); when a row has no such class, the
/// label text is matched instead (labels are localized: zh `卷:` /
/// `ISBN 13:` / `ISBN 10:` / `IPFS:`, en `Volume:` / `ISBN 13:` /
/// `ISBN 10:` / `IPFS:`).
///
/// The IPFS row is special: its visible text is just `CID` /
/// `CID Blake2b` — the real values are the two spans' `data-copy`
/// attributes (first = CID, second = CID Blake2b).
///
/// The `property_volume` row was verified against a second capture
/// (the 阿兹卡班的囚徒 book, which has one): the same uniform
/// pattern, class `property_volume`, label `卷:`, plain-text value
/// (`第21章 赫敏的秘密`). The other rows in that capture confirm the
/// shape too: `property_categories` carries its value inside a link
/// (take the text), and `property_content_type` (`内容类型:` / `书籍`)
/// exists but is not parsed — it is skipped like any other row.
class BookDetailMetadata {
  final String? volume;
  final String? isbn10;
  final String? isbn13;
  final String? ipfsCid;
  final String? ipfsCidBlake2b;

  const BookDetailMetadata({
    this.volume,
    this.isbn10,
    this.isbn13,
    this.ipfsCid,
    this.ipfsCidBlake2b,
  });

  bool get isEmpty =>
      volume == null &&
      isbn10 == null &&
      isbn13 == null &&
      ipfsCid == null &&
      ipfsCidBlake2b == null;
}

/// Parse the detail-page metadata rows out of a detail page's HTML.
/// Missing rows parse to null; empty/whitespace-only values parse to
/// null. A page with no `bookProperty` rows parses to an all-null
/// [BookDetailMetadata] (never throws).
BookDetailMetadata parseBookDetailProperties(String html) {
  final doc = html_parser.parse(html);

  String? byClass(String key) {
    final row = doc.querySelector('div.bookProperty.property_$key');
    if (row == null) return null;
    return _rowValue(row);
  }

  String? byLabel(String label) {
    for (final row in doc.querySelectorAll('div.bookProperty')) {
      final labelEl = row.querySelector('div.property_label');
      if (labelEl == null) continue;
      if (_normalizeLabel(labelEl.text) != label) continue;
      return _rowValue(row);
    }
    return null;
  }

  // IPFS is read from `data-copy` attributes, not from the row text.
  List<String> ipfsCopies() {
    final row = doc.querySelector('div.bookProperty.property_ipfs_cid');
    final scope = row ?? _rowWithLabel(doc, 'ipfs');
    if (scope == null) return const [];
    return scope
        .querySelectorAll('span[data-copy]')
        .map((span) => span.attributes['data-copy']?.trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toList();
  }

  final copies = ipfsCopies();
  return BookDetailMetadata(
    volume: byClass('volume') ?? byLabel('卷') ?? byLabel('volume'),
    isbn10: byClass('isbn_10') ?? byLabel('isbn 10'),
    isbn13: byClass('isbn_13') ?? byLabel('isbn 13'),
    ipfsCid: copies.isNotEmpty ? copies[0] : null,
    ipfsCidBlake2b: copies.length > 1 ? copies[1] : null,
  );
}

/// The row's `property_value` text, trimmed; null when the row has no
/// value element or its text is empty/whitespace-only.
String? _rowValue(dom.Element row) {
  final valueEl = row.querySelector('div.property_value');
  if (valueEl == null) return null;
  final text = valueEl.text.trim();
  return text.isEmpty ? null : text;
}

/// The `bookProperty` row whose label normalizes to [label], or null.
/// Rows without a label element (e.g. `property_language_year`,
/// which is a bare `chinese, 2019` text node) are skipped.
dom.Element? _rowWithLabel(dom.Document doc, String label) {
  for (final row in doc.querySelectorAll('div.bookProperty')) {
    final labelEl = row.querySelector('div.property_label');
    if (labelEl == null) continue;
    if (_normalizeLabel(labelEl.text) == label) return row;
  }
  return null;
}

/// A label with its trailing `:`/`：` stripped and lowercased, so
/// `ISBN 13:` and `isbn 13` compare equal.
String _normalizeLabel(String text) {
  var label = text.trim().toLowerCase();
  while (label.endsWith(':') || label.endsWith('：')) {
    label = label.substring(0, label.length - 1);
  }
  return label.trim();
}
