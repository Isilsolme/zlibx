// Device-side mirror speed test.
//
// SLUM's latency is measured by open-slum.org's server, not from this
// phone — through a VPN the ranking can be completely different. This
// probes each enabled mirror from the device (a timed GET of the
// mirror root) and ranks mirrors by the measured time, so downloads
// try the fastest mirror for *this* network first.
//
// Only the LibGen download path uses the ranking ([rankedUrls]);
// search keeps SLUM order. Results are cached for [cacheTtl]; the
// Mirrors page runs the probe on demand and shows the measured time
// next to SLUM's latency.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'hive_service.dart';
import 'instance_manager.dart';

class MirrorSpeedTest {
  MirrorSpeedTest({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 8),
                headers: const {
                  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 '
                      'Safari/537.36',
                },
              ),
            );

  final Dio _dio;

  static const Duration cacheTtl = Duration(hours: 1);
  static const Duration probeTimeout = Duration(seconds: 8);

  String _cacheKey(MirrorService service) => 'mirror_speed_${service.name}';

  /// Measured milliseconds per host from the last probe, or null when
  /// never probed or stale.
  Map<String, int>? cachedMs(MirrorService service) {
    final raw = HiveService.settingsBox.get(_cacheKey(service));
    if (raw is! Map) return null;
    final at = raw['at'];
    if (at is! int) return null;
    if (DateTime.now().millisecondsSinceEpoch - at >
        cacheTtl.inMilliseconds) {
      return null;
    }
    final ms = raw['ms'];
    if (ms is! Map) return null;
    return {
      for (final entry in ms.entries)
        entry.key.toString(): (entry.value as num).toInt(),
    };
  }

  /// Probe every enabled mirror of [service] from this device and
  /// cache the result. Returns host -> milliseconds (absent = failed).
  Future<Map<String, int?>> probe(MirrorService service) async {
    final urls = await InstanceManager().enabledUrls(service);
    final results = <String, int?>{};
    await Future.wait([
      for (final url in urls)
        _probeOne(url).then((ms) => results[Uri.parse(url).host] = ms),
    ]);
    HiveService.settingsBox.put(_cacheKey(service), {
      'at': DateTime.now().millisecondsSinceEpoch,
      'ms': {
        for (final entry in results.entries)
          if (entry.value != null) entry.key: entry.value,
      },
    });
    return results;
  }

  /// Probe all services (the Mirrors page's speed-test button).
  Future<void> probeAll() async {
    await Future.wait([for (final s in MirrorService.values) probe(s)]);
  }

  /// Enabled mirror URLs for downloads: fresh device measurement first
  /// (fastest first), unmeasured mirrors keep SLUM order after them.
  /// Falls back to plain [InstanceManager.enabledUrls] when nothing
  /// was measured yet.
  Future<List<String>> rankedUrls(MirrorService service) async {
    final urls = await InstanceManager().enabledUrls(service);
    final ms = cachedMs(service);
    if (ms == null || ms.isEmpty) return urls;
    final measured = <String>[];
    final rest = <String>[];
    for (final url in urls) {
      (ms.containsKey(Uri.parse(url).host) ? measured : rest).add(url);
    }
    measured.sort(
      (a, b) =>
          ms[Uri.parse(a).host]!.compareTo(ms[Uri.parse(b).host]!),
    );
    return [...measured, ...rest];
  }

  Future<int?> _probeOne(String url) async {
    final stopwatch = Stopwatch()..start();
    try {
      final res = await _dio
          .get<String>(
            url,
            options: Options(responseType: ResponseType.plain),
          )
          .timeout(probeTimeout);
      stopwatch.stop();
      if (res.statusCode != null && res.statusCode! < 400) {
        return stopwatch.elapsedMilliseconds;
      }
      return null;
    } catch (e) {
      debugPrint('Mirror probe failed for $url: ${e.runtimeType}');
      return null;
    }
  }
}
