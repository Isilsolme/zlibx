import 'package:flutter_test/flutter_test.dart';
import 'package:zlibx/utils/host_utils.dart';

void main() {
  group('isZlibFamilyHost', () {
    test('accepts the Z-Library family, including subdomains', () {
      for (final host in [
        'z-library.sk',
        'reader.z-library.sk',
        'z-lib.fm',
        'Z-LIB.GD',
        'bookroom.lifestyle',
        'reader.bookroom.lifestyle',
        'singlelogin.re',
        '1lib.singlelogin.se',
      ]) {
        expect(isZlibFamilyHost(host), isTrue, reason: host);
      }
    });

    test('rejects look-alike and unrelated hosts', () {
      for (final host in [
        'z-library.evil.com',
        'z-library.sk.evil.com',
        'notbookroom.xyz',
        'evilz-library.sk',
        'bookroom',
        'z-lib',
        'localhost',
        '1.2.3.4',
        'z-library.sk:443',
        'z-library..sk',
        '',
      ]) {
        expect(isZlibFamilyHost(host), isFalse, reason: host);
      }
    });
  });

  group('readerDomainFor', () {
    test('maps a line to its reader host', () {
      expect(readerDomainFor('z-lib.fm'), 'reader.z-lib.fm');
      expect(readerDomainFor('zh.z-lib.fm'), 'reader.z-lib.fm');
      expect(readerDomainFor('bookroom.lifestyle'),
          'reader.bookroom.lifestyle');
    });
  });

  group('isTrustedReaderUrl', () {
    test('accepts the line\'s own reader and bare domain over https', () {
      for (final url in [
        'https://reader.z-lib.fm/read/1',
        'https://z-lib.fm/login',
        'https://reader.z-lib.fm:443/x',
      ]) {
        expect(isTrustedReaderUrl(url, 'z-lib.fm'), isTrue, reason: url);
      }
      expect(isTrustedReaderUrl('https://reader.z-lib.fm/r', 'zh.z-lib.fm'),
          isTrue);
      expect(isTrustedReaderUrl('https://reader.m.cc/r', 'm.cc:8443'), isTrue);
    });

    test('rejects foreign hosts, http and userinfo tricks', () {
      for (final url in [
        'https://evil.com/read/1',
        'https://reader.z-lib.fm.evil.com/x',
        'https://notz-lib.fm/x',
        'https://z-lib.fm@evil.com/x',
        'http://reader.z-lib.fm/x',
        'javascript:alert(1)',
        '',
      ]) {
        expect(isTrustedReaderUrl(url, 'z-lib.fm'), isFalse, reason: url);
      }
      expect(isTrustedReaderUrl('https://reader.z-lib.fm/x', ''), isFalse);
    });
  });
}
