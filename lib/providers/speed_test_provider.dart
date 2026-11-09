import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zlibx/utils/diagnostics.dart';
import 'domain_provider.dart';

enum DomainLatencyStatus { untested, normal, slow, unavailable }

/// A reachable line is healthy through 3000 ms. Higher latency is shown as a
/// warning, while only a failed request is treated as unavailable.
DomainLatencyStatus domainLatencyStatus(int? latencyMs) {
  if (latencyMs == null) return DomainLatencyStatus.untested;
  if (latencyMs < 0) return DomainLatencyStatus.unavailable;
  if (latencyMs <= 3000) return DomainLatencyStatus.normal;
  return DomainLatencyStatus.slow;
}

/// Result of a single domain speed test.
class DomainTestResult {
  final String domain;

  /// null = not tested, -1 = failed, >0 = latency in ms
  int? latencyMs;

  DomainTestResult(this.domain, {this.latencyMs});
}

/// State for the speed test provider.
class SpeedTestState {
  final List<DomainTestResult> results;
  final bool testing;
  final int testedCount;

  const SpeedTestState({
    this.results = const [],
    this.testing = false,
    this.testedCount = 0,
  });

  int get onlineCount =>
      results.where((r) => r.latencyMs != null && r.latencyMs! > 0).length;

  SpeedTestState copyWith({
    List<DomainTestResult>? results,
    bool? testing,
    int? testedCount,
  }) {
    return SpeedTestState(
      results: results ?? this.results,
      testing: testing ?? this.testing,
      testedCount: testedCount ?? this.testedCount,
    );
  }
}

class SpeedTestNotifier extends Notifier<SpeedTestState> {
  late final List<String> _domains;

  /// Max concurrent requests to avoid flooding the network.
  static const int _maxConcurrent = 8;

  @override
  SpeedTestState build() {
    _domains = ref.read(domainListProvider);
    // Was _initResults(): the initial results list is the initial state
    // itself (a state assignment inside build() would be overwritten by
    // its return value).
    return SpeedTestState(
      results: _domains.map((d) => DomainTestResult(d)).toList(),
    );
  }

  /// Run speed test with bounded concurrency (semaphore pattern).
  /// Safe to call multiple times — ignores if already running.
  Future<void> runTest() async {
    if (state.testing) return;

    // Reset results
    final results = _domains.map((d) => DomainTestResult(d)).toList();
    state = SpeedTestState(results: results, testing: true, testedCount: 0);

    int running = 0;
    int index = 0;
    int tested = 0;
    final completer = Completer<void>();

    void scheduleNext() {
      while (running < _maxConcurrent && index < results.length) {
        final r = results[index++];
        running++;
        _checkDomain(r).whenComplete(() {
          running--;
          tested++;
          state = state.copyWith(
            results: List.from(results),
            testedCount: tested,
          );
          if (index < results.length) {
            scheduleNext();
          } else if (running == 0) {
            completer.complete();
          }
        });
      }
    }

    scheduleNext();
    await completer.future;

    // Sort: successful (ascending latency) first, then failed at bottom.
    results.sort((a, b) {
      final la = a.latencyMs ?? 99999;
      final lb = b.latencyMs ?? 99999;
      final aOk = la > 0 && la < 99999;
      final bOk = lb > 0 && lb < 99999;
      if (aOk && !bOk) return -1;
      if (!aOk && bOk) return 1;
      return la.compareTo(lb);
    });

    state = SpeedTestState(
      results: List.from(results),
      testing: false,
      testedCount: tested,
    );
  }

  Future<void> _checkDomain(DomainTestResult result) async {
    final sw = Stopwatch()..start();
    try {
      final uri = Uri.parse('https://${result.domain}/eapi/info/languages');
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 6);

      try {
        final request = await client.getUrl(uri);
        // Headers are enough: the ranking only needs time-to-first-byte,
        // not the whole languages page. (Previously the full body was
        // read and a non-2xx page counted as success when its body
        // contained '"success":1'; that exotic case no longer counts —
        // a healthy mirror answers this endpoint 2xx.)
        final response = await request.close().timeout(
          const Duration(seconds: 8),
        );
        sw.stop();

        final isSuccess =
            response.statusCode >= 200 && response.statusCode < 300;

        result.latencyMs = isSuccess ? sw.elapsedMilliseconds : -1;
      } catch (error) {
        logIgnored('speed_test_provider', error);
        sw.stop();
        result.latencyMs = -1;
      } finally {
        // force: the response body was never read — drop the connection
        // now instead of waiting for the server to finish sending it.
        client.close(force: true);
      }
    } catch (error) {
      logIgnored('speed_test_provider', error);
      sw.stop();
      result.latencyMs = -1;
    }
  }
}

/// Global speed test state — cached across the app lifecycle.
final speedTestProvider =
    NotifierProvider<SpeedTestNotifier, SpeedTestState>(SpeedTestNotifier.new);
