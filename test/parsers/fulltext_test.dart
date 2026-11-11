import 'package:flutter_test/flutter_test.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

/// Full-text results page, SYNTHETIC throughout (invented titles,
/// authors, hashes and tokens — no real user data): 3 real hits, 1
/// hidden fit template, 1 ad slot, tab total 3, 2 pages.
const _resultsHtml = '''
<html><body>
<div class="search-results-tabs-panel">
  <ul id="subprojectsSearch">
    <li class="active">全文检索&nbsp;(3)</li>
  </ul>
</div>
<div id="searchResultBox">
  <div class="book-item resItemBoxBooks ">
    <div class="counter">1</div>
    <z-bookcard id="91001" isbn="" termshash="aaaa1111bbbb2222cccc3333dddd4444" href="/book/AbCdEfGh12/Synthetic-Phrase-Book-One.html" download="/dl/FAKE001" deleted="0" publisher="Synthetic Press" language="english" year="2021" extension="epub" filesize="1.23 MB" rating="4.5" quality="3" user_token="<redacted>" contenttypeparam="" class="ready">
      <img data-src="https://example.com/covers100/fake-cover-1.png">
      <div slot="title">Synthetic Phrase Book One</div>
      <div slot="author">Test Author Alpha</div>
      <div slot="note"></div>
      <div slot="extend">
        <div class="hulltext">
          <div class="ft_highlight">
            <div class="ft_highlight_part">… a plain lead
            <em>synthetic matching phrase</em>
            and a plain tail. …</div>
          </div>
        </div>
      </div>
    </z-bookcard>
  </div>
  <z-promotion book="" async="" id="null" class="ready" demo=""></z-promotion>
  <div class="book-item resItemBoxBooks ">
    <div class="counter">2</div>
    <z-bookcard id="91002" isbn="" termshash="eeee5555ffff6666aaaa7777bbbb8888" href="/book/WxYz0987Ab/Synthetic-Words-Book-Two.html" download="/dl/FAKE002" deleted="9" publisher="" language="english" year="2019" extension="pdf" filesize="9.87 MB" rating="0.0" quality="0" user_token="<redacted>" contenttypeparam="" class="ready">
      <img data-src="https://example.com/covers100/fake-cover-2.png">
      <div slot="title">Synthetic Words Book Two</div>
      <div slot="author">Test Author Beta</div>
      <div slot="note"></div>
      <div slot="extend">
        <div class="hulltext">
          <div class="ft_highlight">
            <div class="ft_highlight_part"><em>first</em> middle <em>second</em></div>
          </div>
        </div>
      </div>
    </z-bookcard>
  </div>
  <div class="book-item resItemBoxBooks ">
    <div class="counter">3</div>
    <z-bookcard id="91003" isbn="" termshash="1234abcd5678efgh9012ijkl3456mnop" href="/book/MnOp3456Qr/Synthetic-Copyright-Book-Three.html" download="" deleted="1" publisher="Synthetic Press" language="" year="" extension="mobi" filesize="0.50 MB" rating="3.0" quality="1" user_token="<redacted>" contenttypeparam="" class="ready">
      <img data-src="https://example.com/covers100/fake-cover-3.png">
      <div slot="title">Synthetic Copyright Book Three</div>
      <div slot="author">Test Author Gamma</div>
      <div slot="note"></div>
      <div slot="extend">
      </div>
    </z-bookcard>
  </div>
  <div class="book-item resItemBoxBooks" hidden aria-hidden="true">
    <div class="counter">0</div>
    <z-bookcard id="99999" isbn="" href="/book/FitTemplate00/synthetic-query-text.html" download="" deleted="0" class="fit ready">
      <div slot="title">synthetic query text</div>
      <div slot="author">synthetic query text</div>
    </z-bookcard>
  </div>
</div>
<script>var pagerOptions = {pagesTotal: 2, pagesSpan: 5, pageCurrent: 1, baseUrl: '/fulltext/'};</script>
</body></html>
''';

const _tokenHtml = '''
<html><body>
<form method="get" id="searchForm" action="/fulltext/">
  <input type="hidden" name="token" value="abcdef12">
  <input type="text" name="q" value="">
</form>
</body></html>
''';

void main() {
  group('parseFullTextSearchPage', () {
    test('parses hits, skips the hidden fit card and the ad slot', () {
      final page = parseFullTextSearchPage(_resultsHtml);
      expect(page.hits, hasLength(3));
      expect(
        page.hits.map((hit) => hit.book.id),
        [91001, 91002, 91003],
      );
    });

    test('total comes from the tab, totalPages from pagerOptions', () {
      final page = parseFullTextSearchPage(_resultsHtml);
      expect(page.total, 3);
      expect(page.totalPages, 2);
    });

    test('total parses the capped "150+" tab form as 150', () {
      final page = parseFullTextSearchPage(
        _resultsHtml.replaceAll('全文检索&nbsp;(3)', '全文检索&nbsp;(150+)'),
      );
      expect(page.total, 150);
    });

    test('parses card fields and the hash from the href', () {
      final page = parseFullTextSearchPage(_resultsHtml);
      final book = page.hits[0].book;
      expect(book.title, 'Synthetic Phrase Book One');
      expect(book.author, 'Test Author Alpha');
      expect(book.hash, 'AbCdEfGh12');
      expect(book.publisher, 'Synthetic Press');
      expect(book.year, 2021);
      expect(book.language, 'english');
      expect(book.extension, 'epub');
      expect(book.filesizeString, '1.23 MB');
      expect(book.interestScore, '4.5');
      expect(book.cover, 'https://example.com/covers100/fake-cover-1.png');
    });

    test('splits the snippet on <em> and folds whitespace', () {
      final page = parseFullTextSearchPage(_resultsHtml);
      final snippet = page.hits[0].snippet;
      expect(
        snippet.map((part) => part.text),
        ['… a plain lead ', 'synthetic matching phrase', ' and a plain tail. …'],
      );
      expect(
        snippet.map((part) => part.highlighted),
        [false, true, false],
      );
    });

    test('handles several <em> runs (words mode)', () {
      final page = parseFullTextSearchPage(_resultsHtml);
      final snippet = page.hits[1].snippet;
      expect(
        snippet.map((part) => part.text),
        ['first', ' middle ', 'second'],
      );
      expect(
        snippet.map((part) => part.highlighted),
        [true, false, true],
      );
    });

    test('marks deleted cards removed with the right reason', () {
      final page = parseFullTextSearchPage(_resultsHtml);
      expect(page.hits[0].removed, isFalse);
      expect(page.hits[0].unavailableReason, isNull);
      expect(page.hits[1].removed, isTrue);
      expect(page.hits[1].unavailableReason, 'removed');
      expect(page.hits[2].removed, isTrue);
      expect(page.hits[2].unavailableReason, 'copyright');
    });

    test('a card without a highlight block has an empty snippet', () {
      final page = parseFullTextSearchPage(_resultsHtml);
      expect(page.hits[2].snippet, isEmpty);
    });

    test('never reads the user_token JWT into any parsed field', () {
      final page = parseFullTextSearchPage(_resultsHtml);
      for (final hit in page.hits) {
        final book = hit.book;
        expect(book.title.contains('<redacted>'), isFalse);
        expect(book.author?.contains('<redacted>') ?? false, isFalse);
        expect(book.cover?.contains('<redacted>') ?? false, isFalse);
        expect(book.hash?.contains('<redacted>') ?? false, isFalse);
      }
    });

    test('total falls back to the hit count when the tab is missing', () {
      final page = parseFullTextSearchPage(
        _resultsHtml.replaceAll('全文检索&nbsp;(3)', '全文检索'),
      );
      expect(page.total, 3);
    });

    test('totalPages defaults to 1 without pagerOptions', () {
      final page = parseFullTextSearchPage(
        _resultsHtml.replaceAll(
          '<script>var pagerOptions = {pagesTotal: 2, pagesSpan: 5, pageCurrent: 1, baseUrl: \'/fulltext/\'};</script>',
          '',
        ),
      );
      expect(page.totalPages, 1);
    });
  });

  group('extractFulltextToken', () {
    test('reads the hidden form field', () {
      expect(extractFulltextToken(_tokenHtml), 'abcdef12');
    });

    test('returns null when the field is missing', () {
      expect(
        extractFulltextToken('<html><body><form></form></body></html>'),
        isNull,
      );
    });

    test('returns null for a malformed value', () {
      for (final bad in ['xyz', 'abc123', 'gggggggg', 'abcdef123']) {
        expect(
          extractFulltextToken(
            '<html><body><input type="hidden" name="token" value="$bad"></body></html>',
          ),
          isNull,
        );
      }
    });
  });

  group('extractFulltextQuery', () {
    test('reads the search form q input', () {
      expect(
        extractFulltextQuery(
          '<html><body><form id="searchForm">'
          '<input type="text" name="q" value="synthetic phrase">'
          '</form></body></html>',
        ),
        'synthetic phrase',
      );
    });

    test('returns null when the q input is missing or empty', () {
      expect(
        extractFulltextQuery('<html><body><form></form></body></html>'),
        isNull,
      );
      // The token fixture's q input is empty.
      expect(extractFulltextQuery(_tokenHtml), isNull);
    });

    test('decodes entities in the echoed query', () {
      expect(
        extractFulltextQuery(
          '<html><body><form id="searchForm">'
          '<input type="text" name="q" value="a &amp; b">'
          '</form></body></html>',
        ),
        'a & b',
      );
    });
  });
}
