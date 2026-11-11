import 'package:flutter_test/flutter_test.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

/// [parseCategoryBooksPage] tests (all data synthetic): a 50-card
/// page with a `pagerOptions` total, the `deleted`/`favorite`
/// flags, the fit-template skip, the empty result, and the missing
/// `#searchResultBox` fallback. Every card carries a `user_token`
/// attribute (a session secret); the value here is a fake marker —
/// the parser must ignore it, and no parsed field may contain it.

/// One synthetic `<z-bookcard>`: id/title/author are generated from
/// [n] so a 50-card page needs no literal HTML.
String _card(
  int n, {
  String deleted = '0',
  String favorite = '0',
  bool fitTemplate = false,
}) {
  final termshash = fitTemplate ? '' : 'aaaa${n.toRadixString(16)}bbbb';
  final classes = fitTemplate ? ' class="fit"' : ' class="ready"';
  return '''
<z-bookcard id="${90000 + n}" isbn="" termshash="$termshash" href="/book/AbCdEfGh${n.toString().padLeft(2, '0')}/Synthetic-Book-$n.html" download="/dl/FAKE${n.toString().padLeft(3, '0')}" deleted="$deleted" favorite="$favorite" publisher="Synthetic Press" language="english" year="2021" extension="epub" filesize="1.23 MB" rating="4.5" quality="3" user_token="FAKE-TOKEN-12345" contenttypeparam=""$classes>
  <img data-src="https://example.com/covers100/fake-cover-$n.png">
  <div slot="title">Synthetic Book $n</div>
  <div slot="author">Test Author $n</div>
  <div slot="note"></div>
  <div slot="extend"></div>
</z-bookcard>''';
}

/// A synthetic category page: [cardCount] cards in `#searchResultBox`
/// `.book-item` wrappers, plus an inline `pagerOptions` definition
/// when [totalPages] is given.
String _page({required int cardCount, int? totalPages, bool withBox = true}) {
  final buffer = StringBuffer('<html><body>');
  if (totalPages != null) {
    buffer.write(
      '<script>var pagerOptions = {pagesTotal: $totalPages, currentPage: 1};</script>',
    );
  }
  if (withBox) {
    buffer.write('<div id="searchResultBox">');
    for (var n = 1; n <= cardCount; n++) {
      buffer.write('<div class="book-item"><div class="counter">$n</div>');
      buffer.write(_card(n));
      buffer.write('</div>');
    }
    buffer.write('</div>');
  } else {
    for (var n = 1; n <= cardCount; n++) {
      buffer.write(_card(n));
    }
  }
  buffer.write('</body></html>');
  return buffer.toString();
}

void main() {
  group('parseCategoryBooksPage', () {
    test('50-card page parses all books with the pagerOptions total', () {
      final page = parseCategoryBooksPage(_page(cardCount: 50, totalPages: 10));
      expect(page.books.length, 50);
      expect(page.totalPages, 10);
      expect(page.books.first.book.id, 90001);
      expect(page.books.first.book.title, 'Synthetic Book 1');
      expect(page.books.first.book.author, 'Test Author 1');
      expect(page.books.last.book.id, 90050);
      expect(page.books.first.book.cover, contains('fake-cover-1.png'));
    });

    test('totalPages is null when the page carries no pagerOptions', () {
      final page = parseCategoryBooksPage(_page(cardCount: 10));
      expect(page.books.length, 10);
      expect(page.totalPages, isNull);
    });

    test('deleted 1/5/9 are kept with their reason, deleted 0 is fine', () {
      final html =
          '<html><body><div id="searchResultBox">'
          '<div class="book-item"><div class="counter">1</div>${_card(1, deleted: '1')}</div>'
          '<div class="book-item"><div class="counter">2</div>${_card(2, deleted: '5')}</div>'
          '<div class="book-item"><div class="counter">3</div>${_card(3, deleted: '9')}</div>'
          '<div class="book-item"><div class="counter">4</div>${_card(4, deleted: '0')}</div>'
          '</div></body></html>';
      final page = parseCategoryBooksPage(html);
      expect(page.books.length, 4);
      expect(page.books[0].removed, isTrue);
      expect(page.books[0].unavailableReason, 'copyright');
      expect(page.books[1].removed, isTrue);
      expect(page.books[1].unavailableReason, 'removed');
      expect(page.books[2].removed, isTrue);
      expect(page.books[2].unavailableReason, 'removed');
      expect(page.books[3].removed, isFalse);
      expect(page.books[3].unavailableReason, isNull);
    });

    test('favorite is parsed from the card attribute', () {
      final html =
          '<html><body><div id="searchResultBox">'
          '<div class="book-item"><div class="counter">1</div>${_card(1, favorite: '1')}</div>'
          '<div class="book-item"><div class="counter">2</div>${_card(2, favorite: '0')}</div>'
          '<div class="book-item"><div class="counter">3</div>${_card(3)}</div>'
          '</div></body></html>';
      final page = parseCategoryBooksPage(html);
      expect(page.books.length, 3);
      expect(page.books[0].isFavorite, isTrue);
      expect(page.books[1].isFavorite, isFalse);
      expect(page.books[2].isFavorite, isFalse);
    });

    test('hidden items, counter-0 items and the fit template are skipped', () {
      final html =
          '<html><body><div id="searchResultBox">'
          '<div class="book-item" hidden><div class="counter">1</div>${_card(1)}</div>'
          '<div class="book-item"><div class="counter">0</div>${_card(2)}</div>'
          '<div class="book-item"><div class="counter">3</div>${_card(3, fitTemplate: true)}</div>'
          '<div class="book-item"><div class="counter">4</div>${_card(4)}</div>'
          '</div></body></html>';
      final page = parseCategoryBooksPage(html);
      expect(
        page.books.map((b) => b.book.id).toList(),
        [90004],
      );
    });

    test('empty result parses to no books but keeps the total', () {
      final page = parseCategoryBooksPage(_page(cardCount: 0, totalPages: 1));
      expect(page.books, isEmpty);
      expect(page.totalPages, 1);
    });

    test('missing #searchResultBox falls back to whole-document cards', () {
      final page = parseCategoryBooksPage(
        _page(cardCount: 3, totalPages: 1, withBox: false),
      );
      expect(page.books.length, 3);
      expect(page.totalPages, 1);
    });

    test('no parsed field ever contains the session user_token', () {
      final page = parseCategoryBooksPage(_page(cardCount: 5, totalPages: 1));
      for (final categoryBook in page.books) {
        final book = categoryBook.book;
        expect(book.title, isNot(contains('FAKE-TOKEN-12345')));
        expect(book.author, isNot(contains('FAKE-TOKEN-12345')));
        expect(book.cover, isNot(contains('FAKE-TOKEN-12345')));
        expect(book.hash, isNot(contains('FAKE-TOKEN-12345')));
      }
    });
  });
}
