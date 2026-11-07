import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zlibx/l10n/book_categories.dart';

void main() {
  group('parseBookCategories', () {
    test('parses a single {id: Name} entry', () {
      final parsed = parseBookCategories('{307: History - World history}');
      expect(parsed.length, 1);
      expect(parsed.first.id, 307);
      expect(parsed.first.name, 'History - World history');
    });

    test('parses several entries, keeping commas inside names', () {
      final parsed = parseBookCategories(
        '{11: Crime, Thrillers & Mystery, 307: History - World history}',
      );
      expect(parsed.length, 2);
      expect(parsed[0].id, 11);
      expect(parsed[0].name, 'Crime, Thrillers & Mystery');
      expect(parsed[1].id, 307);
      expect(parsed[1].name, 'History - World history');
    });

    test('a plain name without braces or id parses as one entry', () {
      final parsed = parseBookCategories('Fiction - Horror');
      expect(parsed.length, 1);
      expect(parsed.first.id, isNull);
      expect(parsed.first.name, 'Fiction - Horror');
    });

    test('missing or empty values parse to nothing', () {
      expect(parseBookCategories(null), isEmpty);
      expect(parseBookCategories(''), isEmpty);
      expect(parseBookCategories('   '), isEmpty);
      expect(parseBookCategories('{}'), isEmpty);
    });
  });

  group('localizedBookCategoryName', () {
    const worldHistory = (id: 307, name: 'History - World history');
    const horror = (id: 271, name: 'Fiction - Horror');

    test('zh shows the Chinese name', () {
      expect(
        localizedBookCategoryName(worldHistory, const Locale('zh')),
        '历史 - 世界历史',
      );
      expect(
        localizedBookCategoryName(horror, const Locale('zh')),
        '小说 - 恐怖',
      );
    });

    test('zh_Hant shows the Traditional name', () {
      const hant = Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hant',
      );
      expect(
        localizedBookCategoryName(worldHistory, hant),
        '歷史 - 世界歷史',
      );
      expect(
        localizedBookCategoryName(worldHistory, const Locale('zh', 'TW')),
        '歷史 - 世界歷史',
      );
    });

    test('other locales and unknown ids fall back to the English name', () {
      expect(
        localizedBookCategoryName(worldHistory, const Locale('en')),
        'History - World history',
      );
      expect(
        localizedBookCategoryName(worldHistory, const Locale('ja')),
        'History - World history',
      );
      expect(
        localizedBookCategoryName(
          (id: 999999, name: 'Something New'),
          const Locale('zh'),
        ),
        'Something New',
      );
      expect(
        localizedBookCategoryName(
          (id: null, name: 'Fiction - Horror'),
          const Locale('zh'),
        ),
        'Fiction - Horror',
      );
    });
  });
}
