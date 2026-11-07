import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:zlibx/services/booklist_html_cache.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('booklist_html_cache');
    Hive.init(tempDir.path);
    await Hive.openBox(BooklistHtmlCache.boxName);
  });

  setUp(() async {
    await Hive.box(BooklistHtmlCache.boxName).clear();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('stores and returns HTML by URL', () {
    BooklistHtmlCache.store(
      'https://example.com/booklists/my',
      '<html>mine</html>',
    );
    expect(
      BooklistHtmlCache.get('https://example.com/booklists/my'),
      '<html>mine</html>',
    );
  });

  test('returns null for unknown URLs', () {
    expect(
      BooklistHtmlCache.get('https://example.com/booklists'),
      isNull,
    );
  });

  test('ignores empty URL and empty HTML', () {
    BooklistHtmlCache.store('', '<html/>');
    BooklistHtmlCache.store('https://example.com/x', '');
    expect(BooklistHtmlCache.get(''), isNull);
    expect(BooklistHtmlCache.get('https://example.com/x'), isNull);
  });

  test('a newer store overwrites an older one', () {
    const url = 'https://example.com/booklists/my';
    BooklistHtmlCache.store(url, '<html>old</html>');
    BooklistHtmlCache.store(url, '<html>new</html>');
    expect(BooklistHtmlCache.get(url), '<html>new</html>');
  });

  test('entries older than the TTL read as absent', () {
    final box = Hive.box(BooklistHtmlCache.boxName);
    final staleAt = DateTime.now()
        .subtract(BooklistHtmlCache.ttl + const Duration(seconds: 1))
        .millisecondsSinceEpoch;
    box.put('https://example.com/old', {
      'at': staleAt,
      'html': '<html>old</html>',
    });
    expect(BooklistHtmlCache.get('https://example.com/old'), isNull);
  });

  test('corrupt entries read as absent', () {
    final box = Hive.box(BooklistHtmlCache.boxName);
    box.put('https://example.com/broken', {'nope': true});
    box.put('https://example.com/broken-at', {
      'at': 'not-a-number',
      'html': '<html/>',
    });
    expect(BooklistHtmlCache.get('https://example.com/broken'), isNull);
    expect(
      BooklistHtmlCache.get('https://example.com/broken-at'),
      isNull,
    );
  });

  test('evicts the oldest entries past the cap', () {
    final box = Hive.box(BooklistHtmlCache.boxName);
    // Hand-built entries with increasing timestamps: the first one
    // is the oldest and must go when one more store pushes the box
    // past the cap. (Hand-built timestamps are long past the TTL,
    // so presence is checked on the box itself, not through get.)
    for (var i = 0; i < BooklistHtmlCache.maxEntries; i++) {
      box.put('https://example.com/$i', {
        'at': 1000 + i,
        'html': '<html>$i</html>',
      });
    }
    BooklistHtmlCache.store(
      'https://example.com/new',
      '<html>new</html>',
    );
    expect(box.length, BooklistHtmlCache.maxEntries);
    expect(box.containsKey('https://example.com/0'), isFalse);
    expect(box.containsKey('https://example.com/1'), isTrue);
    expect(
      BooklistHtmlCache.get('https://example.com/new'),
      '<html>new</html>',
    );
  });

  test('clear empties the cache', () {
    BooklistHtmlCache.store(
      'https://example.com/booklists/my',
      '<html>mine</html>',
    );
    BooklistHtmlCache.clear();
    expect(
      BooklistHtmlCache.get('https://example.com/booklists/my'),
      isNull,
    );
  });
}
