import 'package:flutter_test/flutter_test.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

/// Minimal booklist detail page modelled on the live
/// `/booklist/4088695/62a0c2/001.html` document captured 2026-11-07.
/// The `user_token` value is FAKE — the real capture carried a JWT for
/// the signed-in user, which must never be stored in a fixture.
const _detailHtml = '''
<div class="readlist-view">
<z-bookcard library id="5288001" isbn="978-7-01-000000-0" termshash="abc" href="/book/a1b2c3d4e5f6a7b8/slug-one.html" download="/dl/5288001/xyz" deleted="0" publisher="出版社A" language="Chinese" year="2020" extension="epub" filesize="13.38 MB" rating="5.0" quality="1" user_token="FAKE.JWT.TOKEN-DO-NOT-USE" read="https://reader.example.com/read/abc" contentTypeParam="" booklisted="true" booklistsindex="555001">
<img data-src="https://cdn.example.com/covers100/collections/userbooks/1.jpg">
<div slot="title">第一本书</div>
<div slot="author">作者甲; 作者乙</div>
<div slot="note">笔记</div>
<div slot="extend"><z-tags bookid="5288001"></z-tags></div>
</z-bookcard>
<z-bookcard library id="5722200" href="/book/0123456789abcdef/slug-two.html" deleted="0" publisher="出版社B" language="English" year="2021" extension="pdf" filesize="2.06 MB" rating="4.5" read="https://reader.example.com/read/def">
<img src="https://cdn.example.com/covers100/2.jpg">
<div slot="title">Second Book</div>
<div slot="author">Author B</div>
</z-bookcard>
<z-bookcard library id="999" href="/book/deadbeef/slug-deleted.html" deleted="1"><div slot="title">已删除</div></z-bookcard>
<z-bookcard library href="/book/nonumeric/slug.html" deleted="0"><div slot="title">无 id</div></z-bookcard>
</div>
''';

void main() {
  group('parseBooklistDetailBooks', () {
    test('parses cards, skips deleted and id-less cards', () {
      final books = parseBooklistDetailBooks(_detailHtml);
      expect(books.length, 2);

      final first = books[0];
      expect(first.id, 5288001);
      expect(first.title, '第一本书');
      expect(first.hash, 'a1b2c3d4e5f6a7b8');
      expect(first.author, '作者甲; 作者乙');
      expect(
        first.cover,
        'https://cdn.example.com/covers100/collections/userbooks/1.jpg',
      );
      expect(first.publisher, '出版社A');
      expect(first.year, 2020);
      expect(first.language, 'Chinese');
      expect(first.extension, 'epub');
      expect(first.filesizeString, '13.38 MB');
      expect(first.interestScore, '5.0');
      expect(first.readOnlineUrl, 'https://reader.example.com/read/abc');
      // Detail-only fields: the membership-row id and the per-book
      // note from this own-list card.
      expect(first.readlistBookId, 555001);
      expect(first.note, '笔记');

      final second = books[1];
      expect(second.id, 5722200);
      expect(second.title, 'Second Book');
      expect(second.hash, '0123456789abcdef');
      // Cover falls back to plain src when data-src is absent.
      expect(second.cover, 'https://cdn.example.com/covers100/2.jpg');
      expect(second.extension, 'pdf');
      // A card without booklistsindex / note carries neither.
      expect(second.readlistBookId, isNull);
      expect(second.note, isNull);
    });

    test('never reads the user_token attribute', () {
      final books = parseBooklistDetailBooks(_detailHtml);
      expect(books.length, 2);
      for (final book in books) {
        expect(
          book.toJson().values,
          everyElement(isNot('FAKE.JWT.TOKEN-DO-NOT-USE')),
        );
      }
    });

    test('resolves relative covers against baseUrl', () {
      const html = '''
<z-bookcard id="1" href="/book/abcdef/slug.html" deleted="0">
<img data-src="/covers100/x.jpg">
<div slot="title">T</div>
</z-bookcard>
''';
      final books = parseBooklistDetailBooks(
        html,
        baseUrl: 'https://zh.z-library.sk',
      );
      expect(books.length, 1);
      expect(books[0].cover, 'https://zh.z-library.sk/covers100/x.jpg');
    });

    test('a page with no cards parses to an empty list', () {
      expect(
        parseBooklistDetailBooks('<html><body>not a detail page</body></html>'),
        isEmpty,
      );
      expect(parseBooklistDetailBooks(''), isEmpty);
    });
  });
}
