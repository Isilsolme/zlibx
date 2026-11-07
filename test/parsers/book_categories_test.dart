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
        '世界历史',
      );
      expect(
        localizedBookCategoryName(horror, const Locale('zh')),
        '恐怖',
      );
    });

    test('zh_Hant shows the Traditional name', () {
      const hant = Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hant',
      );
      expect(
        localizedBookCategoryName(worldHistory, hant),
        '世界歷史',
      );
      expect(
        localizedBookCategoryName(worldHistory, const Locale('zh', 'TW')),
        '世界歷史',
      );
    });

    test('a long parent name is dropped and the region shortens (613)', () {
      const euroAmericanPhilosophy = (
        id: 613,
        name: 'Society, Politics & Philosophy - European & american philosophy',
      );
      expect(
        localizedBookCategoryName(
          euroAmericanPhilosophy,
          const Locale('zh'),
        ),
        '欧美哲学',
      );
      expect(
        localizedBookCategoryName(
          euroAmericanPhilosophy,
          const Locale.fromSubtags(
            languageCode: 'zh',
            scriptCode: 'Hant',
          ),
        ),
        '歐美哲學',
      );
    });

    test('a doubled parent word is shown once', () {
      expect(
        localizedBookCategoryName(
          (id: 528, name: 'Psychology - Psychology - theory, history & research'),
          const Locale('zh'),
        ),
        '心理学：理论、历史与研究',
      );
      expect(
        localizedBookCategoryName(
          (id: 387, name: 'Linguistics - Linguistics'),
          const Locale('zh'),
        ),
        '语言学',
      );
      expect(
        localizedBookCategoryName(
          (id: 528, name: 'Psychology - Psychology - theory, history & research'),
          const Locale.fromSubtags(
            languageCode: 'zh',
            scriptCode: 'Hant',
          ),
        ),
        '心理學：理論、歷史與研究',
      );
      expect(
        localizedBookCategoryName(
          (id: 999999, name: 'Psychology - Psychology - theory, history & research'),
          const Locale('en'),
        ),
        'Psychology - theory, history & research',
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
