import 'package:flutter_test/flutter_test.dart';
import 'package:zlibx/core/annas_archive.dart';

const _baseUrl = 'https://annas-archive.org';

/// Minimal search-results page: one container with the selectors
/// `parseSearchResults` reads (title link, author/publisher
/// `/search?q=` siblings, info line, md5 thumbnail link).
const _searchHtml = '''
<div class="flex pt-3 pb-3 border-b">
<a class="line-clamp-[3] js-vim-focus" href="/md5/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">三体</a>
<a href="/search?q=author%3A%E5%88%98%E6%85%88%E6%AC%A3">刘慈欣</a>
<a href="/search?q=publisher%3A%E9%87%8D%E5%BA%86%E5%87%BA%E7%89%88%E7%A4%BE">重庆出版社</a>
<div class="text-gray-800">Chinese [zh] · EPUB · 3.12 MB</div>
<a href="/md5/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"><img src="https://covers.example.com/1.jpg"></a>
</div>
<div class="flex pt-3 pb-3 border-b">
<a class="line-clamp-[3] js-vim-focus" href="/md5/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb">Second Book</a>
<a href="/search?q=author%3A...">Author B</a>
<a href="/search?q=publisher%3A...">Publisher B</a>
<div class="text-gray-800">English [en] · PDF · 2.06 MB</div>
</div>
''';

/// Minimal `/md5/` detail page.
const _detailHtml = '''
<div class="main-inner">
<div class="font-semibold text-2xl">三体</div>
<a class="text-base" href="/search?q=author%3A...">刘慈欣</a>
<a href="/search?q=publisher%3A...">重庆出版社</a>
<div id="list_cover_1"><img src="https://covers.example.com/1.jpg"></div>
<div class="text-gray-800">Chinese [zh] · EPUB · 3.12 MB</div>
<div class="js-md5-top-box-description">
<div class="text-xs text-gray-500 uppercase">Description</div>
<div>一本关于三体的书。</div>
</div>
<ul class="list-inside"><li><a href="/slow_download/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">Slow download</a></li></ul>
</div>
''';

void main() {
  group('ArchiveParsing.cleanText', () {
    test('removes emoji and collapses whitespace', () {
      expect(ArchiveParsing.cleanText('  Hello 🌍  world 🔍 '), 'Hello world');
      expect(ArchiveParsing.cleanText('a\n\n  b'), 'a b');
    });
  });

  group('ArchiveParsing.formatFromInfo', () {
    test('detects pdf/cbr/cbz, defaults to epub', () {
      expect(ArchiveParsing.formatFromInfo('English [en] pdf 2 MB'), 'pdf');
      expect(ArchiveParsing.formatFromInfo('cbr 10 MB'), 'cbr');
      expect(ArchiveParsing.formatFromInfo('cbz 10 MB'), 'cbz');
      expect(ArchiveParsing.formatFromInfo('EPUB 3 MB'), 'epub');
      expect(ArchiveParsing.formatFromInfo(null), 'epub');
      expect(ArchiveParsing.formatFromInfo(''), 'epub');
    });
  });

  group('ArchiveParsing.md5FromLink', () {
    test('takes the segment after md5', () {
      expect(
        ArchiveParsing.md5FromLink('/md5/abc123/'),
        'abc123',
      );
      expect(
        ArchiveParsing.md5FromLink('https://annas-archive.org/md5/def456'),
        'def456',
      );
      expect(ArchiveParsing.md5FromLink(''), '');
    });
  });

  group('ArchiveParsing.parseSearchResults', () {
    test('parses title, author, publisher, info and thumbnail', () {
      final books = ArchiveParsing.parseSearchResults(
        _searchHtml,
        baseUrl: _baseUrl,
      );
      expect(books.length, 2);

      final first = books[0];
      expect(first.title, '三体');
      expect(first.author, '刘慈欣');
      expect(first.publisher, '重庆出版社');
      expect(first.md5, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
      expect(
        first.link,
        '$_baseUrl/md5/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
      expect(first.thumbnail, 'https://covers.example.com/1.jpg');
      expect(first.info, 'Chinese [zh] · EPUB · 3.12 MB');
      expect(first.format, 'epub');

      expect(books[1].title, 'Second Book');
      expect(books[1].format, 'pdf');
      expect(books[1].thumbnail, isNull);
    });

    test('fileType filter drops non-matching results', () {
      final books = ArchiveParsing.parseSearchResults(
        _searchHtml,
        baseUrl: _baseUrl,
        fileType: 'pdf',
      );
      expect(books.length, 1);
      expect(books[0].title, 'Second Book');
    });

    test('falls back to md5 links when containers are absent', () {
      const html = '''
<div class="results">
<div><a href="/md5/cccccccccccccccccccccccccccccccc">Fallback Book</a></div>
</div>
''';
      final books = ArchiveParsing.parseSearchResults(
        html,
        baseUrl: _baseUrl,
      );
      expect(books.length, 1);
      expect(books[0].title, 'Fallback Book');
      expect(books[0].md5, 'cccccccccccccccccccccccccccccccc');
      expect(books[0].author, isNull);
    });

    test('a page with no results parses to an empty list', () {
      expect(
        ArchiveParsing.parseSearchResults(
          '<html><body>no results</body></html>',
          baseUrl: _baseUrl,
        ),
        isEmpty,
      );
    });
  });

  group('ArchiveParsing.parseBookDetails', () {
    test('parses title, author, description and slow link', () {
      final details = ArchiveParsing.parseBookDetails(
        _detailHtml,
        url: '$_baseUrl/md5/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/三体',
        baseUrl: _baseUrl,
      );
      expect(details, isNotNull);
      expect(details!.title, '三体');
      expect(details.author, '刘慈欣');
      expect(details.publisher, '重庆出版社');
      expect(details.md5, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
      expect(details.thumbnail, 'https://covers.example.com/1.jpg');
      expect(details.description, '一本关于三体的书。');
      expect(
        details.slowDownloadUrl,
        '$_baseUrl/slow_download/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
    });

    test('returns null without a book record', () {
      expect(
        ArchiveParsing.parseBookDetails(
          '<html><body>not a book page</body></html>',
          url: '$_baseUrl/md5/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/x',
          baseUrl: _baseUrl,
        ),
        isNull,
      );
      expect(
        ArchiveParsing.parseBookDetails(
          '<div class="main-inner"><p>no title here</p></div>',
          url: '$_baseUrl/md5/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/x',
          baseUrl: _baseUrl,
        ),
        isNull,
      );
    });

    test('missing description degrades to an empty string', () {
      const html = '''
<div class="main-inner">
<div class="font-semibold text-2xl">T</div>
</div>
''';
      final details = ArchiveParsing.parseBookDetails(
        html,
        url: '$_baseUrl/md5/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/T',
        baseUrl: _baseUrl,
      );
      expect(details, isNotNull);
      expect(details!.description, '');
      expect(details.slowDownloadUrl, isNull);
    });
  });

  group('ArchiveParsing challenge and page checks', () {
    test('isChallengeResponse recognises bot walls', () {
      expect(
        ArchiveParsing.isChallengeResponse(
          statusCode: 403,
          body: 'checking your browser before accessing the site',
        ),
        isTrue,
      );
      expect(
        ArchiveParsing.isChallengeResponse(
          statusCode: 200,
          body: '<title>Just a moment...</title>',
        ),
        isTrue,
      );
      expect(
        ArchiveParsing.isChallengeResponse(
          statusCode: 200,
          body: 'plain page',
          cfMitigated: 'challenge',
        ),
        isTrue,
      );
      expect(
        ArchiveParsing.isChallengeResponse(
          statusCode: 200,
          body: '<title>Anna\'s Archive</title>results',
        ),
        isFalse,
      );
    });

    test('isArchivePage checks the title', () {
      expect(
        ArchiveParsing.isArchivePage(
          '<title>Anna\'s Archive</title>',
        ),
        isTrue,
      );
      expect(ArchiveParsing.isArchivePage('<title>Google</title>'), isFalse);
    });

    test('extractSlowDownloadLink pulls the link out of the slow page', () {
      const html = '''
<p class="mb-4 text-xl font-bold"><a href="https://dl.example.com/f.epub">Download</a></p>
''';
      expect(
        ArchiveParsing.extractSlowDownloadLink(html),
        'https://dl.example.com/f.epub',
      );
      expect(
        ArchiveParsing.extractSlowDownloadLink('<p>no link</p>'),
        isNull,
      );
    });
  });

  group('ArchiveParsing URL helpers', () {
    test('buildSearchUrl: plain query omits page 1', () {
      expect(
        ArchiveParsing.buildSearchUrl(
          baseUrl: _baseUrl,
          query: 'harry potter',
        ),
        '$_baseUrl/search?q=harry+potter',
      );
    });

    test('buildSearchUrl: filters and page 2 are appended', () {
      final url = ArchiveParsing.buildSearchUrl(
        baseUrl: _baseUrl,
        query: 'x',
        sort: 'newest',
        content: 'book_nonfiction',
        page: 2,
      );
      expect(url.contains('sort=newest'), isTrue);
      expect(url.contains('content=book_nonfiction'), isTrue);
      expect(url.contains('&page=2'), isTrue);
    });

    test('resolveUrl keeps absolute hrefs and joins relative ones', () {
      expect(
        ArchiveParsing.resolveUrl(_baseUrl, '/md5/abc'),
        '$_baseUrl/md5/abc',
      );
      expect(
        ArchiveParsing.resolveUrl(
          _baseUrl,
          'https://other.example.com/md5/abc',
        ),
        'https://other.example.com/md5/abc',
      );
    });
  });
}
