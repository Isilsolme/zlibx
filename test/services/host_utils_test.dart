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
}
