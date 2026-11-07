import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zlibx/services/instance_manager.dart';
import 'package:zlibx/services/libgen_service.dart';

/// Minimal `ads.php` page: the `get.php?md5=` link, the `table#main`
/// metadata row and the cover image.
const _adsHtml = '''
<table id="main">
<tr><td>
Title: 资本论（全三卷）<br>Author(s): 马克思<br>Publisher: 人民出版社<br>Year: 2018<br>Language: Chinese<br>
</td></tr>
<tr><td><img src="/covers/123.jpg"></td></tr>
<tr><td><a href="get.php?md5=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa&key=1">GET</a></td></tr>
</table>
''';

LibgenService _service() => LibgenService(
      dio: Dio(),
      instanceManager: InstanceManager.forTest(),
    );

void main() {
  group('LibgenService.parseAdsCover', () {
    test('resolves a relative cover against the mirror', () {
      expect(
        LibgenService.parseAdsCover(_adsHtml, 'https://libgen.is'),
        'https://libgen.is/covers/123.jpg',
      );
    });

    test('keeps an absolute cover and rejects missing images', () {
      const absolute = '''
<table id="main"><tr><td><img src="https://cdn.example.com/c.jpg"></td></tr></table>
''';
      expect(
        LibgenService.parseAdsCover(absolute, 'https://libgen.is'),
        'https://cdn.example.com/c.jpg',
      );
      expect(
        LibgenService.parseAdsCover(
          '<table id="main"><tr><td>no image</td></tr></table>',
          'https://libgen.is',
        ),
        isNull,
      );
      expect(
        LibgenService.parseAdsCover(
          '<table id="main"><tr><td><img src=""></td></tr></table>',
          'https://libgen.is',
        ),
        isNull,
      );
      expect(
        LibgenService.parseAdsCover('<p>no table</p>', 'https://libgen.is'),
        isNull,
      );
    });
  });

  group('LibgenService.parseAdsPage', () {
    test('parses title, author, md5, mirror and cover', () {
      final info = _service().parseAdsPage(
        _adsHtml,
        'https://libgen.is',
        'https://libgen.is/ads.php?md5=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
      expect(info, isNotNull);
      expect(info!.title, '资本论（全三卷）');
      expect(info.author, '马克思');
      expect(info.md5, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
      expect(
        info.mirror,
        'https://libgen.is/get.php?md5=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa&key=1',
      );
      expect(info.thumbnail, 'https://libgen.is/covers/123.jpg');
      expect(info.publisher, '人民出版社, 2018');
      expect(info.info, 'Chinese');
      expect(info.format, 'epub');
    });

    test('returns null on markup it does not recognise', () {
      final service = _service();
      expect(
        service.parseAdsPage(
          '<table id="main"><tr><td>No get link here</td></tr></table>',
          'https://libgen.is',
          'https://libgen.is/ads.php?md5=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
        isNull,
      );
      expect(
        service.parseAdsPage(
          '<p>no table at all</p>',
          'https://libgen.is',
          'https://libgen.is/ads.php?md5=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
        isNull,
      );
      expect(
        service.parseAdsPage(
          '<table id="main"><tr><td><a href="get.php?md5=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">GET</a></td></tr><tr><td>No title row</td></tr></table>',
          'https://libgen.is',
          'https://libgen.is/ads.php?md5=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
        isNull,
      );
    });
  });
}
