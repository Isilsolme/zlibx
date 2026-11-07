import 'package:flutter_test/flutter_test.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

const _baseUrl = 'https://zh.z-library.sk';

/// Minimal `/booklists/my` page modelled on the live HTML captured
/// 2026-11-06: list 001 carries its books in the carousel, the second
/// list has no `id` attribute (the plural-href path), and the third
/// element is the create button (no topic) and must be skipped.
const _myBooklistsHtml = '''
<html><body>
<z-booklist id="4088695" href="/booklist/4088695/62a0c2/001.html" topic="001" author="徕" authorprofile="/profile/35899435/5a9053" quantity="4" views="12">
<a href="/book/abc123def456/slug-one.html"><z-cover id="5740686" author="霍格尔·丹贝克" title="你学的数学可能是假的"><img data-src="https://cdn.example.com/covers200/collections/userbooks/1.jpg"></z-cover></a>
<a href="/book/9876543210abcdef/slug-two.html"><z-cover id="5288001" author="作者二" title="第二本书"><img data-src="https://cdn.example.com/covers200/collections/userbooks/2.jpg"></z-cover></a>
</z-booklist>
<z-booklist href="/booklists/777/xyz/公开书单.html" topic="公开书单" quantity="2"></z-booklist>
<z-booklist href="/booklists/999/x/y.html"></z-booklist>
<script>var pagerOptions = {pagesTotal: 3, foo: 1};</script>
</body></html>
''';

void main() {
  group('parseBooklistsPage', () {
    test('parses lists, carousel preview books and page count', () {
      final page = parseBooklistsPage(_myBooklistsHtml, baseUrl: _baseUrl);
      expect(page.totalPages, 3);
      expect(page.lists.length, 2);

      final first = page.lists[0];
      expect(first.id, '4088695');
      expect(first.name, '001');
      expect(first.author, '/profile/35899435/5a9053');
      expect(first.count, 4);
      expect(first.views, '12');
      expect(
        first.url,
        '$_baseUrl/booklist/4088695/62a0c2/001.html',
      );
      expect(
        first.coverUrl,
        'https://cdn.example.com/covers200/collections/userbooks/1.jpg',
      );
      expect(first.previewBooks.length, 2);
      expect(first.previewBooks[0].id, 5740686);
      expect(first.previewBooks[0].title, '你学的数学可能是假的');
      expect(first.previewBooks[0].author, '霍格尔·丹贝克');
      expect(first.previewBooks[0].hash, 'abc123def456');
      expect(
        first.previewBooks[0].cover,
        'https://cdn.example.com/covers200/collections/userbooks/1.jpg',
      );
      expect(first.previewBooks[1].id, 5288001);
      expect(first.previewBooks[1].hash, '9876543210abcdef');
    });

    test('falls back to the href id for the plural /booklists/ shape', () {
      final page = parseBooklistsPage(_myBooklistsHtml, baseUrl: _baseUrl);
      final second = page.lists[1];
      expect(second.id, '777');
      expect(second.name, '公开书单');
      expect(second.count, 2);
      expect(second.previewBooks, isEmpty);
    });

    test('singular /booklist/ href without an id attribute still parses', () {
      // Regression test for build #46: the old code only recognised the
      // plural "booklists" segment, so every real list was dropped and
      // the screen showed "no booklists".
      const html = '''
<z-booklist href="/booklist/4088695/62a0c2/001.html" topic="001" quantity="4"></z-booklist>
''';
      final page = parseBooklistsPage(html, baseUrl: _baseUrl);
      expect(page.lists.length, 1);
      expect(page.lists[0].id, '4088695');
    });

    test('empty page parses to an empty list with unknown page count', () {
      final page = parseBooklistsPage(
        '<html><body><p>nothing here</p></body></html>',
        baseUrl: _baseUrl,
      );
      expect(page.lists, isEmpty);
      expect(page.totalPages, 0);
    });

    test('a list without a page count reports totalPages 0', () {
      const html = '''
<z-booklist id="1" href="/booklist/1/a/x.html" topic="X"></z-booklist>
''';
      final page = parseBooklistsPage(html, baseUrl: _baseUrl);
      expect(page.lists.length, 1);
      expect(page.totalPages, 0);
    });
  });
}
