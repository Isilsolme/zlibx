import 'package:flutter_test/flutter_test.dart';
import 'package:zlibx/core/slum.dart';

/// Minimal SLUM service page: one plain mirror, one DDoS-Guard
/// protected mirror, one down mirror without status/latency readings.
const _slumHtml = '''
<div class="card" id="zlibrary.z-lib.fm">
<a class="card-title" href="https://z-lib.fm">Z-Library</a>
<span class="status-badge up">UP</span>
<div>Status: 200</div>
<div>Latency: 123ms</div>
</div>
<div class="card" id="annas-archive.org">
<a class="card-title" href="https://annas-archive.org">Anna's Archive</a>
<span class="status-badge protected">PROTECTED</span>
<strong>Protected Site</strong><span>DDoS-Guard</span>
<div>Status: 200</div>
<div>Latency: 456ms</div>
</div>
<div class="card" id="libgen.is">
<a class="card-title" href="https://libgen.is">LibGen</a>
<span class="status-badge down">DOWN</span>
</div>
''';

void main() {
  group('parseSlumPage', () {
    test('parses status, protection, latency and HTTP status', () {
      final sites = parseSlumPage(
        _slumHtml,
        service: MirrorService.zlibrary,
      );
      expect(sites.length, 3);

      final plain = sites[0];
      expect(plain.host, 'z-lib.fm');
      expect(plain.url, 'https://z-lib.fm');
      expect(plain.status, SlumStatus.up);
      expect(plain.protection, Protection.none);
      expect(plain.httpStatus, 200);
      expect(plain.latencyMs, 123);
      expect(plain.isDown, isFalse);
      expect(plain.isAttemptable, isTrue);

      final guarded = sites[1];
      expect(guarded.host, 'annas-archive.org');
      expect(guarded.status, SlumStatus.protected);
      expect(guarded.protection, Protection.ddosGuard);
      expect(guarded.latencyMs, 456);

      final down = sites[2];
      expect(down.host, 'libgen.is');
      expect(down.status, SlumStatus.down);
      expect(down.protection, Protection.unknown);
      expect(down.httpStatus, isNull);
      expect(down.latencyMs, isNull);
      expect(down.isDown, isTrue);
      expect(down.isAttemptable, isFalse);
    });

    test('falls back to timeline readings when the badge is absent', () {
      const html = '''
<div class="card" id="x.example.com">
<a class="card-title" href="https://x.example.com">X</a>
<div data-status="degraded"></div>
<div data-status="up"></div>
</div>
''';
      final sites = parseSlumPage(html, service: MirrorService.zlibrary);
      expect(sites.length, 1);
      // Timeline readings are oldest first; the last one wins.
      expect(sites[0].status, SlumStatus.up);
    });

    test('a card without a link is skipped', () {
      const html = '''
<div class="card" id="x.example.com"><span class="status-badge up">UP</span></div>
''';
      expect(
        parseSlumPage(html, service: MirrorService.zlibrary),
        isEmpty,
      );
    });

    test('welib keeps only welib hosts and honours skipHosts', () {
      const html = '''
<div class="card" id="a.welib.org">
<a class="card-title" href="https://a.welib.org">WeLib</a>
<span class="status-badge up">UP</span>
</div>
<div class="card" id="other.example.com">
<a class="card-title" href="https://other.example.com">Other</a>
<span class="status-badge up">UP</span>
</div>
''';
      final kept = parseSlumPage(html, service: MirrorService.welib);
      expect(kept.length, 1);
      expect(kept[0].host, 'a.welib.org');
      expect(
        parseSlumPage(
          html,
          service: MirrorService.welib,
          skipHosts: {'a.welib.org'},
        ),
        isEmpty,
      );
    });
  });

  group('sortSlumSites', () {
    test('down sorts last, then protection rank, then latency', () {
      const fast = SlumSite(
        service: MirrorService.zlibrary,
        url: 'https://fast.example.com',
        host: 'fast.example.com',
        status: SlumStatus.up,
        protection: Protection.none,
        latencyMs: 100,
      );
      const slow = SlumSite(
        service: MirrorService.zlibrary,
        url: 'https://slow.example.com',
        host: 'slow.example.com',
        status: SlumStatus.up,
        protection: Protection.none,
        latencyMs: 200,
      );
      const guarded = SlumSite(
        service: MirrorService.zlibrary,
        url: 'https://guarded.example.com',
        host: 'guarded.example.com',
        status: SlumStatus.protected,
        protection: Protection.ddosGuard,
        latencyMs: 50,
      );
      const down = SlumSite(
        service: MirrorService.zlibrary,
        url: 'https://down.example.com',
        host: 'down.example.com',
        status: SlumStatus.down,
        protection: Protection.none,
        latencyMs: 10,
      );
      final sorted = sortSlumSites([down, guarded, slow, fast]);
      expect(
        sorted.map((s) => s.host).toList(),
        [
          'fast.example.com',
          'slow.example.com',
          'guarded.example.com',
          'down.example.com',
        ],
      );
    });
  });

  group('normalizeSlumUrl', () {
    test('adds the scheme and strips trailing slashes', () {
      expect(normalizeSlumUrl('z-lib.fm/'), 'https://z-lib.fm');
      expect(normalizeSlumUrl('http://a.b/'), 'http://a.b');
      expect(normalizeSlumUrl('https://a.b//'), 'https://a.b');
    });
  });
}
