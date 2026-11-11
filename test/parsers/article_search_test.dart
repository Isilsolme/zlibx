import 'package:flutter_test/flutter_test.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

/// Article search results page, SYNTHETIC throughout (invented
/// titles, authors, hashes and ids — no real user data): 3 real
/// articles (one removed by copyright), 1 hidden fit template, 1 ad
/// slot, tab total 3, 2 pages. Card shape mirrors the 2026-11-11
/// capture of `/s/{query}?content_type=article` (zh.z-library.sk).
const _resultsHtml = '''
<html><body>
<div class="search-results-tabs-panel">
  <ul id="searchModeTabs">
    <li class="active">文章&nbsp;(3)</li>
  </ul>
</div>
<div id="searchResultBox">
  <div class="book-item resItemBoxBooks ">
    <div class="counter">1</div>
    <z-bookcard id="91001" isbn="" termshash="aaaa1111bbbb2222cccc3333dddd4444" href="/book/AbCdEfGh12/Synthetic-Article-One.html" download="/dl/FAKE001" deleted="0" publisher="" language="中文" year="" extension="pdf" filesize="1.31 MB" rating="0.0" quality="4" user_token="<redacted>" contenttypeparam="?content_type=article" class="ready">
      <img data-src="https://example.com/covers100/fake-cover-1.png">
      <div slot="title">Synthetic Article One: Third Party Wealth Management</div>
      <div slot="author">Synthetic Securities Co., Ltd.</div>
      <div slot="note"></div>
      <div slot="extend"></div>
    </z-bookcard>
  </div>
  <z-promotion book="" async="" id="null" class="ready" demo=""></z-promotion>
  <div class="book-item resItemBoxBooks">
    <div class="counter">2</div>
    <z-bookcard id="91002" isbn="" termshash="eeee5555ffff6666aaaa7777bbbb8888" href="/book/WxYz0987Ab/Synthetic-Article-Two.html" download="/dl/FAKE002" deleted="0" publisher="Synthetic Journal" language="english" year="2014" extension="pdf" filesize="7.11 MB" rating="4.9" quality="5.0" user_token="<redacted>" contenttypeparam="?content_type=article" class="fit ready">
      <img data-src="">
      <div slot="title">Synthetic Article Two</div>
      <div slot="author">Test Author Beta</div>
      <div slot="note"></div>
      <div slot="extend"></div>
    </z-bookcard>
  </div>
  <div class="book-item resItemBoxBooks ">
    <div class="counter">3</div>
    <z-bookcard id="91003" isbn="" termshash="1234abcd5678efgh9012ijkl3456mnop" href="/book/MnOp3456Qr/Synthetic-Copyright-Article-Three.html" download="" deleted="1" publisher="Synthetic Press" language="" year="" extension="pdf" filesize="0.50 MB" rating="3.0" quality="1" user_token="<redacted>" contenttypeparam="?content_type=article" class="ready">
      <img data-src="/covers100/fake-relative-cover-3.png">
      <div slot="title">Synthetic Copyright Article Three</div>
      <div slot="author">Test Author Gamma</div>
      <div slot="note"></div>
      <div slot="extend"></div>
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
</body></html>
''';

/// Same page without the mode tab and without the pager script:
/// total falls back to the parsed card count, pages to 1.
const _bareHtml = '''
<html><body>
<div id="searchResultBox">
  <div class="book-item resItemBoxBooks ">
    <div class="counter">1</div>
    <z-bookcard id="92001" isbn="" href="/book/BareHash0001/Bare-Synthetic-Article.html" download="/dl/FAKE003" deleted="0" extension="pdf" filesize="2.00 MB" class="ready">
      <img data-src="https://example.com/covers100/fake-cover-4.png">
      <div slot="title">Bare Synthetic Article</div>
      <div slot="author">Test Author Delta</div>
    </z-bookcard>
  </div>
</div>
</body></html>
''';

/// A page whose mode tab carries the English label (non-zh mirror).
const _englishTabHtml = '''
<html><body>
<div id="searchModeTabs"><li class="active">Articles&nbsp;(150+)</li></div>
<div id="searchResultBox"></div>
</body></html>
''';

const _resultsHtmlWithPager = '''
<html><body>
<div id="searchResultBox"></div>
<script>var pagerOptions = {pagesTotal: 5, pagesSpan: 5, pageCurrent: 1};</script>
</body></html>
''';

void main() {
  group('parseArticleSearchPage', () {
    test('parses articles, skips the hidden fit card and the ad slot', () {
      final page = parseArticleSearchPage(_resultsHtml);
      expect(page.articles, hasLength(3));
      expect(
        page.articles.map((a) => a.id),
        [91001, 91002, 91003],
      );
      // The tab count (3), not the raw card count (4, fit included).
      expect(page.total, 3);
    });

    test('maps every card attribute onto the Article model', () {
      final page = parseArticleSearchPage(_resultsHtml);
      final first = page.articles[0];
      expect(first.title,
          'Synthetic Article One: Third Party Wealth Management');
      expect(first.author, 'Synthetic Securities Co., Ltd.');
      expect(first.hash, 'AbCdEfGh12');
      expect(first.href, '/book/AbCdEfGh12/Synthetic-Article-One.html');
      expect(first.url,
          '/book/AbCdEfGh12/Synthetic-Article-One.html'); // no baseUrl → stays relative
      expect(first.cover,
          'https://example.com/covers100/fake-cover-1.png');
      expect(first.publisher, isNull); // empty attribute → null
      expect(first.year, isNull); // empty attribute → null
      expect(first.language, '中文');
      expect(first.extension, 'pdf');
      expect(first.filesizeString, '1.31 MB');
      expect(first.rating, '0.0');
      expect(first.quality, '4');
      expect(first.downloadPath, '/dl/FAKE001');
      expect(first.removed, isFalse);
      expect(first.unavailableReason, isNull);
    });

    test('resolves href, cover and download against the site base', () {
      final page = parseArticleSearchPage(_resultsHtml,
          baseUrl: 'https://zh.z-library.sk');
      final first = page.articles[0];
      expect(
        first.url,
        'https://zh.z-library.sk/book/AbCdEfGh12/Synthetic-Article-One.html',
      );
      final third = page.articles[2];
      expect(
        third.cover,
        'https://zh.z-library.sk/covers100/fake-relative-cover-3.png',
      );
    });

    test('keeps a removed card, flags it and clears its download', () {
      final page = parseArticleSearchPage(_resultsHtml);
      final removed = page.articles[2];
      expect(removed.removed, isTrue);
      expect(removed.unavailableReason, 'copyright');
      expect(removed.downloadPath, isNull); // empty download attribute
      expect(removed.publisher, 'Synthetic Press');
      expect(removed.quality, '1');
    });

    test('parses year, publisher and empty cover on a filled card', () {
      final page = parseArticleSearchPage(_resultsHtml);
      final second = page.articles[1];
      expect(second.year, 2014);
      expect(second.publisher, 'Synthetic Journal');
      expect(second.language, 'english');
      expect(second.rating, '4.9');
      expect(second.quality, '5.0');
      expect(second.cover, isNull); // empty data-src → null
    });

    test('falls back to the card count and 1 page without tab/pager',
        () {
      final page = parseArticleSearchPage(_bareHtml);
      expect(page.articles, hasLength(1));
      expect(page.articles.first.id, 92001);
      expect(page.articles.first.hash, 'BareHash0001');
      expect(page.articles.first.title, 'Bare Synthetic Article');
      expect(page.total, 1);
      expect(page.totalPages, 1);
    });

    test('reads the English tab label and its trailing plus', () {
      final page = parseArticleSearchPage(_englishTabHtml);
      expect(page.total, 150);
    });

    test('reads totalPages from the pagerOptions script', () {
      final page = parseArticleSearchPage(_resultsHtmlWithPager);
      expect(page.totalPages, 5);
    });
  });

  group('extractArticleSearchQuery', () {
    test('returns the echoed query from the form input', () {
      const html = '''
<html><body>
<form id="searchForm" action="/s/">
  <input type="text" maxlength="200" name="q" id="searchFieldx" value="synthetic query">
</form>
</body></html>
''';
      expect(extractArticleSearchQuery(html), 'synthetic query');
    });

    test('returns null when the form carries no q input', () {
      const html = '<html><body><form></form></body></html>';
      expect(extractArticleSearchQuery(html), isNull);
    });
  });
}
