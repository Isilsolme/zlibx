import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zlibx/services/booklist_share_codec.dart';

// Regression tests for the share-code / deep-link size caps (audit 3.3):
// the app accepts booklists from other apps (olib:// deep links, shared
// text / JSON files), so an unbounded gzip.decode / file read is a
// compression bomb: a few KB can expand to hundreds of MB and OOM the app.
void main() {
  group('tryDecode size caps', () {
    test('gzip bomb (small input, >2MB output) returns null', () {
      // 3 MB of repeated text compresses to a few KB, but the
      // decompressed JSON is over the 2 MB cap.
      final payload = jsonEncode({
        'v': 1,
        'b': [
          {'id': '1', 't': 'x' * (3 * 1024 * 1024)},
        ],
      });
      final compressed = gzip.encode(utf8.encode(payload));
      // Compressed form is tiny, so the d-param length cap is not hit;
      // only the gzip output cap should reject it.
      expect(compressed.length, lessThan(512 * 1024));
      final uri =
          'olib://booklist?d=${base64UrlEncode(compressed)}';
      expect(BooklistShareCodec.tryDecode(uri), isNull);
    });

    test('d parameter over 512KB is rejected without decoding', () {
      final longD = 'A' * (BooklistShareCodec.maxDParamChars + 1);
      expect(
        BooklistShareCodec.tryDecode('olib://booklist?d=$longD'),
        isNull,
      );
    });

    test('JSON with 2500 books is capped at 2000 entries', () {
      final many = List.generate(2500, (i) => {'id': '$i'});
      final json = jsonEncode({'v': 1, 'books': many});
      final data = BooklistShareCodec.tryDecode(json);
      expect(data, isNotNull);
      expect(data!.entries.length, BooklistShareCodec.maxBookEntries);
    });

    test('compact URI with 2500 books is capped at 2000 entries', () {
      final entries = List.generate(
        2500,
        (i) => BooklistEntry(id: '$i'),
      );
      final uri = BooklistShareCodec.encodeFullUri(
        BooklistShareData(entries: entries),
      );
      final data = BooklistShareCodec.tryDecode(uri);
      expect(data, isNotNull);
      expect(data!.entries.length, BooklistShareCodec.maxBookEntries);
    });

    test('a normal small share still decodes', () {
      const data = BooklistShareData(
        entries: [BooklistEntry(id: '123', title: 'Test')],
        name: 'My list',
      );
      final uri = BooklistShareCodec.encodeFullUri(data);
      final decoded = BooklistShareCodec.tryDecode(uri);
      expect(decoded, isNotNull);
      expect(decoded!.entries.length, 1);
      expect(decoded.entries.first.id, '123');
      expect(decoded.entries.first.title, 'Test');
      expect(decoded.name, 'My list');
    });
  });
}
