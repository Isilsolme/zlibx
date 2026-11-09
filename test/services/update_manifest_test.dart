import 'package:flutter_test/flutter_test.dart';
import 'package:zlibx/services/update/update_manifest.dart';

void main() {
  group('update link allow-list', () {
    test('keeps documented netdisks and GitHub, drops everything else', () {
      final m = UpdateManifest.parse('''
notes
<!-- olib-update
min_version: 1.4.0
百度网盘: https://pan.baidu.com/s/abc?pwd=1234
夸克网盘: https://pan.quark.cn/s/xyz
Evil: https://evil.example.com/zlibx.apk
Plain: http://pan.baidu.com/s/abc
Spoof: https://pan.baidu.com@evil.example.com/x
Suffix: https://pan.baidu.com.evil.example.com/x
-->''');
      expect(m.links.map((l) => l.name), ['百度网盘', '夸克网盘']);
      expect(m.minVersion, '1.4.0');
      // Dropped links are counted (names only) instead of silently
      // disappearing, so the update dialog can warn about them.
      expect(m.droppedLinkNames, ['Evil', 'Plain', 'Spoof', 'Suffix']);
      expect(m.droppedLinkCount, 4);
    });

    test('non-link lines are not counted as dropped', () {
      final m = UpdateManifest.parse('''
<!-- olib-update
min_version: 1.4.0
备注：请用官网下载
百度网盘: https://pan.baidu.com/s/abc
-->''');
      expect(m.links.map((l) => l.name), ['百度网盘']);
      expect(m.droppedLinkCount, 0);
    });

    test('subdomains of an allowed host pass, look-alikes do not', () {
      expect(UpdateManifest.isAllowedLink('https://gist.github.com/x'), isTrue);
      expect(UpdateManifest.isAllowedLink('https://notgithub.com/x'), isFalse);
      expect(UpdateManifest.isAllowedLink('ftp://github.com/x'), isFalse);
    });
  });
}
