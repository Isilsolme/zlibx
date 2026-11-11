import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

// Full-text search request tests (all data synthetic): the token page
// and the results page are canned HTML served by a fake adapter, so
// no network runs. Covers the query the plugin sends (q / token /
// type / e / order / page and the repeated `languages[]` /
// `extensions[]` keys), the 200-char cap, token caching, the
// stale-token retry, and the challenge-page error shape the
// provider's solver fallback keys on.

const _tokenHtml = '''
<html><body>
<form method="get" id="searchForm" action="/fulltext/">
  <input type="hidden" name="token" value="abcdef12">
</form>
</body></html>
''';

const _emptyResultsHtml = '''
<html><body>
<div class="search-results-tabs-panel">
  <ul id="subprojectsSearch">
    <li class="active">全文检索&nbsp;(0)</li>
  </ul>
</div>
<div id="searchResultBox">
</div>
</body></html>
''';

const _oneHitHtml = '''
<html><body>
<div class="search-results-tabs-panel">
  <ul id="subprojectsSearch">
    <li class="active">全文检索&nbsp;(1)</li>
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
            <div class="ft_highlight_part"><em>synthetic matching phrase</em></div>
          </div>
        </div>
      </div>
    </z-bookcard>
  </div>
</div>
</body></html>
''';

/// Serves the token page and canned results pages. Records every
/// request URI so the tests can assert on the exact query the plugin
/// built.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({this.resultsHtml = _emptyResultsHtml});

  final String resultsHtml;

  /// The search answers 302 once, then 200 (stale-token retry).
  bool failSearchWith302Once = false;

  /// The search answers 200 with a browser-check page.
  bool challengeSearch = false;

  /// The token page carries no token field.
  bool tokenMissing = false;

  final List<String> requestedUris = [];
  int searchCalls = 0;
  int tokenCalls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final uri = options.uri;
    requestedUris.add(uri.toString());
    if (uri.path == '/fulltext' && !uri.hasQuery) {
      tokenCalls++;
      if (tokenMissing) {
        return _html('<html><body><form id="searchForm"></form></body></html>');
      }
      return _html(_tokenHtml);
    }
    if (uri.path == '/fulltext/') {
      searchCalls++;
      if (challengeSearch) {
        return _html(
          '<html><body>Checking your browser before accessing the site</body></html>',
        );
      }
      if (failSearchWith302Once && searchCalls == 1) {
        return ResponseBody.fromString(
          '',
          302,
          headers: {Headers.contentTypeHeader: ['text/html']},
        );
      }
      return _html(resultsHtml);
    }
    return ResponseBody.fromString(
      '',
      404,
      headers: {Headers.contentTypeHeader: ['text/html']},
    );
  }

  ResponseBody _html(String html, {int statusCode = 200}) {
    return ResponseBody.fromString(
      html,
      statusCode,
      headers: {Headers.contentTypeHeader: ['text/html']},
    );
  }

  @override
  void close({bool force = false}) {}
}

ZLibraryApi _apiWith(_FakeAdapter adapter) {
  return ZLibraryApi(dio: Dio()..httpClientAdapter = adapter);
}

Uri _searchUri(_FakeAdapter adapter) {
  final uri = adapter.requestedUris.lastWhere(
    (u) => Uri.parse(u).path == '/fulltext/',
  );
  return Uri.parse(uri);
}

void main() {
  group('searchFullText request', () {
    test('sends q, token, type=phrase and page by default', () async {
      final adapter = _FakeAdapter();
      final api = _apiWith(adapter);
      final response = await api.searchFullText(query: 'synthetic phrase');
      expect(response.success, isTrue);
      final uri = _searchUri(adapter);
      expect(uri.queryParameters['q'], 'synthetic phrase');
      expect(uri.queryParameters['token'], 'abcdef12');
      expect(uri.queryParameters['type'], 'phrase');
      expect(uri.queryParameters['page'], '1');
      expect(uri.queryParameters.containsKey('e'), isFalse);
    });

    test('exact sends e=1 and words sends type=words', () async {
      final adapter = _FakeAdapter();
      final api = _apiWith(adapter);
      await api.searchFullText(
        query: 'synthetic phrase',
        type: 'words',
        exact: true,
      );
      final uri = _searchUri(adapter);
      expect(uri.queryParameters['type'], 'words');
      expect(uri.queryParameters['e'], '1');
    });

    test('passes order, page, year range and filters through', () async {
      final adapter = _FakeAdapter();
      final api = _apiWith(adapter);
      await api.searchFullText(
        query: 'synthetic phrase',
        yearFrom: 2000,
        yearTo: 2020,
        languages: ['chinese', 'english'],
        extensions: ['epub', 'pdf'],
        order: 'filesize',
        page: 2,
      );
      final uri = _searchUri(adapter);
      expect(uri.queryParameters['yearFrom'], '2000');
      expect(uri.queryParameters['yearTo'], '2020');
      expect(uri.queryParameters['order'], 'filesize');
      expect(uri.queryParameters['page'], '2');
      // Repeated keys with brackets: Dio's default list format
      // appends `[]` to the bare key.
      expect(
        uri.queryParametersAll['languages[]'],
        ['chinese', 'english'],
      );
      expect(
        uri.queryParametersAll['extensions[]'],
        ['epub', 'pdf'],
      );
      expect(uri.query.contains('languages[][]'), isFalse);
      expect(uri.query.contains('extensions[][]'), isFalse);
    });

    test('caps the query at 200 characters', () async {
      final adapter = _FakeAdapter();
      final api = _apiWith(adapter);
      final longQuery = 'x' * 250;
      await api.searchFullText(query: longQuery);
      final uri = _searchUri(adapter);
      expect(uri.queryParameters['q'], 'x' * 200);
    });

    test('fetches the token once and reuses it', () async {
      final adapter = _FakeAdapter();
      final api = _apiWith(adapter);
      await api.searchFullText(query: 'first');
      await api.searchFullText(query: 'second');
      expect(adapter.tokenCalls, 1);
      expect(adapter.searchCalls, 2);
    });

    test('fails with the token error when the page carries none', () async {
      final adapter = _FakeAdapter()..tokenMissing = true;
      final api = _apiWith(adapter);
      final response = await api.searchFullText(query: 'synthetic phrase');
      expect(response.success, isFalse);
      expect(response.error, fulltextTokenUnavailable);
    });

    test('retries once with a fresh token after a 302', () async {
      final adapter = _FakeAdapter()..failSearchWith302Once = true;
      final api = _apiWith(adapter);
      final response = await api.searchFullText(query: 'synthetic phrase');
      expect(response.success, isTrue);
      expect(adapter.searchCalls, 2);
      expect(adapter.tokenCalls, 2);
    });

    test('surfaces a challenge page as a browser-check error', () async {
      final adapter = _FakeAdapter()..challengeSearch = true;
      final api = _apiWith(adapter);
      final response = await api.searchFullText(query: 'synthetic phrase');
      expect(response.success, isFalse);
      expect(response.error, contains('browser check'));
    });

    test('returns parsed hits', () async {
      final adapter = _FakeAdapter(resultsHtml: _oneHitHtml);
      final api = _apiWith(adapter);
      final response = await api.searchFullText(query: 'synthetic phrase');
      expect(response.success, isTrue);
      final page = response.data!;
      expect(page.total, 1);
      expect(page.hits, hasLength(1));
      expect(page.hits[0].book.title, 'Synthetic Phrase Book One');
      expect(page.hits[0].snippet.single.highlighted, isTrue);
    });
  });

  group('fulltextPageUrl', () {
    test('writes bracket keys explicitly and carries the token', () {
      final api = _apiWith(_FakeAdapter());
      final url = api.fulltextPageUrl(
        query: 'synthetic phrase',
        type: 'words',
        exact: true,
        languages: ['chinese', 'english'],
        extensions: ['epub'],
        order: 'titleA',
        page: 3,
        token: 'abcdef12',
      );
      expect(url, contains('/fulltext/?'));
      expect(url, contains('q=synthetic%20phrase'));
      expect(url, contains('token=abcdef12'));
      expect(url, contains('type=words'));
      expect(url, contains('e=1'));
      expect(url, contains('languages[]=chinese&languages[]=english'));
      expect(url, contains('extensions[]=epub'));
      expect(url, contains('order=titleA'));
      expect(url, contains('page=3'));
    });
  });
}
