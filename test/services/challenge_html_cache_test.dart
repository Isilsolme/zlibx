import 'package:flutter_test/flutter_test.dart';
import 'package:zlibx/services/challenge_html_cache.dart';

void main() {
  setUp(ChallengeHtmlCache.clear);

  test('stores and returns a page, clear() empties it', () {
    ChallengeHtmlCache.store('https://a.example/x', '<html>a</html>');
    expect(ChallengeHtmlCache.get('https://a.example/x'), '<html>a</html>');
    expect(ChallengeHtmlCache.entryCount, 1);
    ChallengeHtmlCache.clear();
    expect(ChallengeHtmlCache.get('https://a.example/x'), isNull);
    expect(ChallengeHtmlCache.entryCount, 0);
    expect(ChallengeHtmlCache.totalChars, 0);
  });

  test('entry count is capped and the oldest pages go first', () {
    for (var i = 0; i < ChallengeHtmlCache.maxEntries + 6; i++) {
      ChallengeHtmlCache.store('https://a.example/$i', 'page $i');
    }
    expect(ChallengeHtmlCache.entryCount, ChallengeHtmlCache.maxEntries);
    expect(ChallengeHtmlCache.get('https://a.example/0'), isNull);
    expect(
      ChallengeHtmlCache.get(
        'https://a.example/${ChallengeHtmlCache.maxEntries + 5}',
      ),
      isNotNull,
    );
  });

  test('total size is capped', () {
    final big = 'x' * 2500000;
    ChallengeHtmlCache.store('https://a.example/1', big);
    ChallengeHtmlCache.store('https://a.example/2', big);
    ChallengeHtmlCache.store('https://a.example/3', big);
    expect(
      ChallengeHtmlCache.totalChars,
      lessThanOrEqualTo(ChallengeHtmlCache.maxTotalChars),
    );
    expect(ChallengeHtmlCache.get('https://a.example/1'), isNull);
    expect(ChallengeHtmlCache.get('https://a.example/3'), isNotNull);
  });

  test('a single oversized page is not cached', () {
    final huge = 'x' * (ChallengeHtmlCache.maxEntryChars + 1);
    ChallengeHtmlCache.store('https://a.example/huge', huge);
    expect(ChallengeHtmlCache.get('https://a.example/huge'), isNull);
    expect(ChallengeHtmlCache.totalChars, 0);
  });

  test('re-storing a URL replaces it without double counting', () {
    ChallengeHtmlCache.store('https://a.example/x', 'aaaa');
    ChallengeHtmlCache.store('https://a.example/x', 'bb');
    expect(ChallengeHtmlCache.entryCount, 1);
    expect(ChallengeHtmlCache.totalChars, 2);
    expect(ChallengeHtmlCache.get('https://a.example/x'), 'bb');
  });
}
