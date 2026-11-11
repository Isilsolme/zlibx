import 'package:flutter_test/flutter_test.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

/// Detail-page metadata rows modelled on the live DOM captured
/// 2026-11-11 (Firefox Inspector, zh.z-library.sk): the first book
/// has no volume row; the second book (阿兹卡班的囚徒) VERIFIED the
/// volume row — same uniform pattern, class `property_volume`,
/// label `卷:`, plain-text value. Full row order on that book:
/// categories, content_type, volume, year, publisher, language,
/// pages, isbn_10, isbn_13, series, file, ipfs_cid, language_year.
/// The categories value is a link (take the text); content_type is
/// not parsed and must be skipped cleanly.
const _detailHtml = '''
<html><body><div class="bookDetailsBox">
<div class="bookProperty property_categories">
  <div class="property_label">种类:</div>
  <div class="property_value"><a href="/category/153/Childrens-Books-Science-Fiction-Fantasy">Children's Books - Science Fiction &amp; Fantasy</a></div>
</div>
<div class="bookProperty property_content_type">
  <div class="property_label">内容类型:</div>
  <div class="property_value">书籍</div>
</div>
<div class="bookProperty property_volume">
  <div class="property_label">卷:</div>
  <div class="property_value">第21章 赫敏的秘密</div>
</div>
<div class="bookProperty property_year">
  <div class="property_label">年:</div>
  <div class="property_value">2016</div>
</div>
<div class="bookProperty property_publisher">
  <div class="property_label">出版社:</div>
  <div class="property_value">人民文学出版社</div>
</div>
<div class="bookProperty property_language">
  <div class="property_label">语言:</div>
  <div class="property_value"><span class="text-capitalize">中文</span></div>
</div>
<div class="bookProperty property_pages">
  <div class="property_label">页:</div>
  <div class="property_value"><span title="Pages paperback">1298</span></div>
</div>
<div class="bookProperty property_isbn_10">
  <div class="property_label">ISBN 10:</div>
  <div class="property_value">7020034632</div>
</div>
<div class="bookProperty property_isbn_13">
  <div class="property_label">ISBN 13:</div>
  <div class="property_value">9787020034635</div>
</div>
<div class="bookProperty property_series">
  <div class="property_label">系列:</div>
  <div class="property_value">阿兹卡班的囚徒</div>
</div>
<div class="bookProperty property_file">
  <div class="property_label">文件:</div>
  <div class="property_value">EPUB, 28.34 MB</div>
</div>
<div class="bookProperty property_ipfs_cid">
  <div class="property_label">IPFS:</div>
  <div class="property_value">
    <span class="z-copy-icon tooltip-init" data-copy="QMwWibgnN41PZc8pTnUhoY9TWkz3AKZTWcUxWHZ4w5Uf">CID</span>
    ,
    <span class="z-copy-icon tooltip-init" data-copy="bafykbzacecp2ciwl2u5vlutjc2eohitquswtwybrygiyacjp7z3frdbogkkala">CID Blake2b</span>
  </div>
</div>
<div class="bookProperty property_language_year">chinese, 2016</div>
</div></body></html>
''';

void main() {
  group('parseBookDetailProperties', () {
    test('extracts all five values, both IPFS CIDs from data-copy', () {
      final meta = parseBookDetailProperties(_detailHtml);
      expect(meta.volume, '第21章 赫敏的秘密');
      expect(meta.isbn10, '7020034632');
      expect(meta.isbn13, '9787020034635');
      expect(meta.ipfsCid, 'QMwWibgnN41PZc8pTnUhoY9TWkz3AKZTWcUxWHZ4w5Uf');
      expect(
        meta.ipfsCidBlake2b,
        'bafykbzacecp2ciwl2u5vlutjc2eohitquswtwybrygiyacjp7z3frdbogkkala',
      );
      expect(meta.isEmpty, isFalse);
    });

    test('missing rows parse to null', () {
      const html = '''
<html><body><div class="bookDetailsBox">
<div class="bookProperty property_year">
  <div class="property_label">年:</div>
  <div class="property_value">2016</div>
</div>
<div class="bookProperty property_publisher">
  <div class="property_label">出版社:</div>
  <div class="property_value">人民文学出版社</div>
</div>
</div></body></html>
''';
      final meta = parseBookDetailProperties(html);
      expect(meta.volume, isNull);
      expect(meta.isbn10, isNull);
      expect(meta.isbn13, isNull);
      expect(meta.ipfsCid, isNull);
      expect(meta.ipfsCidBlake2b, isNull);
      expect(meta.isEmpty, isTrue);
    });

    test('empty and whitespace-only values parse to null', () {
      const html = '''
<html><body><div class="bookDetailsBox">
<div class="bookProperty property_volume">
  <div class="property_label">卷:</div>
  <div class="property_value">   </div>
</div>
<div class="bookProperty property_isbn_13">
  <div class="property_label">ISBN 13:</div>
  <div class="property_value"></div>
</div>
<div class="bookProperty property_ipfs_cid">
  <div class="property_label">IPFS:</div>
  <div class="property_value"><span data-copy="">CID</span></div>
</div>
</div></body></html>
''';
      final meta = parseBookDetailProperties(html);
      expect(meta.volume, isNull);
      expect(meta.isbn13, isNull);
      expect(meta.ipfsCid, isNull);
      expect(meta.ipfsCidBlake2b, isNull);
      expect(meta.isEmpty, isTrue);
    });

    test('a page with no bookProperty rows parses to all null', () {
      final meta = parseBookDetailProperties(
        '<html><body><p>no metadata here</p></body></html>',
      );
      expect(meta.isEmpty, isTrue);
      expect(meta.volume, isNull);
      expect(meta.isbn10, isNull);
      expect(meta.isbn13, isNull);
      expect(meta.ipfsCid, isNull);
      expect(meta.ipfsCidBlake2b, isNull);
    });

    test('falls back to matching the label text without a class key', () {
      const html = '''
<html><body><div class="bookDetailsBox">
<div class="bookProperty">
  <div class="property_label">Volume:</div>
  <div class="property_value">Part Two</div>
</div>
<div class="bookProperty">
  <div class="property_label">ISBN 13:</div>
  <div class="property_value">9780000000000</div>
</div>
</div></body></html>
''';
      final meta = parseBookDetailProperties(html);
      expect(meta.volume, 'Part Two');
      expect(meta.isbn13, '9780000000000');
      expect(meta.isbn10, isNull);
      expect(meta.ipfsCid, isNull);
    });
  });
}
