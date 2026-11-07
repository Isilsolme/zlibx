import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zlibx/utils/file_utils.dart';

// Regression tests for the download filename length cap (audit 3.1):
// Android caps a single filename at 255 bytes (UTF-8) and a Chinese
// character is 3 bytes, so a long title used to fail the write.
// Filenames are now truncated to maxFileNameBytes (200) by rune,
// never splitting a multi-byte character.
void main() {
  group('truncateUtf8ByBytes', () {
    test('short string is unchanged', () {
      expect(truncateUtf8ByBytes('hello.pdf', 200), 'hello.pdf');
    });

    test('ASCII is cut to exactly maxBytes', () {
      expect(truncateUtf8ByBytes('abcdefghij', 5), 'abcde');
    });

    test('CJK is cut on a character boundary', () {
      const title = '你学的数学可能是假的';
      final cut = truncateUtf8ByBytes(title, 10);
      // 10 bytes hold 3 Chinese chars (9 bytes); the 4th would not fit.
      expect(cut, '你学的');
      expect(utf8.encode(cut).length, lessThanOrEqualTo(10));
      // Decodes cleanly: no character was split in half.
      expect(utf8.decode(utf8.encode(cut)), cut);
    });

    test('astral characters (emoji) are never split', () {
      const emoji = '📚📚📚📚📚';
      final cut = truncateUtf8ByBytes(emoji, 10);
      expect(cut, '📚📚');
      expect(cut.runes.length, 2);
    });

    test('empty input and zero cap', () {
      expect(truncateUtf8ByBytes('', 200), '');
      expect(truncateUtf8ByBytes('abc', 0), '');
    });
  });

  group('buildSafeFileName', () {
    test('100 Chinese chars stay within the byte cap', () {
      final name = '汉' * 100;
      final file = buildSafeFileName(name, extension: 'epub');
      expect(utf8.encode(file).length, lessThanOrEqualTo(maxFileNameBytes));
      expect(file, endsWith('.epub'));
      // Still a readable prefix, not garbage.
      expect(file.startsWith('汉'), isTrue);
    });

    test('illegal characters are stripped', () {
      expect(
        buildSafeFileName('a/b:c*d?e"f<g>h|i', extension: 'pdf'),
        'abcdefghi.pdf',
      );
    });

    test('empty name falls back to a timestamped name', () {
      final file = buildSafeFileName('///', extension: 'epub');
      expect(file, startsWith('file_'));
      expect(file, endsWith('.epub'));
    });

    test('no extension returns just the truncated name', () {
      final file = buildSafeFileName('x' * 300);
      expect(utf8.encode(file).length, lessThanOrEqualTo(maxFileNameBytes));
      expect(file, 'x' * 200);
    });
  });
}
