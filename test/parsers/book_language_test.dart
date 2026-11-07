import 'package:flutter_test/flutter_test.dart';
import 'package:zlibx/core/book_language.dart';

void main() {
  group('bookLanguageName', () {
    test('bracketed code wins', () {
      expect(bookLanguageName('English [en] · EPUB'), 'English');
      expect(bookLanguageName('[zh] Chinese'), 'Chinese');
    });

    test('leading code or name is recognised', () {
      expect(bookLanguageName('zh, English'), 'Chinese');
      expect(bookLanguageName('Chinese, something else'), 'Chinese');
      expect(bookLanguageName('ja'), 'Japanese');
    });

    test('unknown, empty and null inputs give null', () {
      expect(bookLanguageName('Klingon'), isNull);
      expect(bookLanguageName('[xx]'), isNull);
      expect(bookLanguageName(''), isNull);
      expect(bookLanguageName('   '), isNull);
      expect(bookLanguageName(null), isNull);
    });
  });
}
