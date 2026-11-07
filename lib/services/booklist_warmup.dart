import 'package:olib_api_plugin/olib_api_plugin.dart';

import 'booklist_html_cache.dart';
import 'challenge_html_cache.dart';
import 'external_logger.dart';
import 'wall_cookie_bridge.dart';
import 'webview_challenge_solver.dart';

/// Background warm-up for the two fixed booklist list pages
/// (`/booklists/my` and `/booklists`, page 1, no query).
///
/// The list pages are single HTML documents, and a cold open waits on
/// the WebView challenge solver when the mirror walls Dio. Warming
/// them once after sign-in — solving the wall in a headless WebView,
/// bridging the clearance cookies to Dio, and persisting the HTML —
/// means the first real open paints from cache and its refresh goes
/// through fast Dio instead of solving again.
///
/// Headless only: the solve never consults the visible solver
/// fallback, so this can never pop a challenge screen over the home
/// page. Fire-and-forget and single-flight per app launch; only
/// runs while signed in. All errors are swallowed (logged only) —
/// a failed warm-up just means the first open solves on demand, as
/// today.
class BooklistWarmup {
  BooklistWarmup._();

  static final AppLogger _logger = AppLogger();

  /// Single-flight per app launch: the warm-up runs at most once,
  /// however often the home screen mounts.
  static bool _started = false;

  static Future<void> warmUp({
    required ZLibraryApi api,
    required User? user,
  }) async {
    final userKey = user?.remixUserkey;
    if (user == null || userKey == null || userKey.isEmpty) return;
    if (_started) return;
    _started = true;
    if (!WebviewChallengeSolver.isSupported) return;
    try {
      // The URLs must match the booklists screen's page-1 loads
      // exactly (same builder, same arguments) so the warmed HTML
      // and cookies land under the cache keys the screen reads.
      await _warmOne(
        api,
        user,
        api.booklistsPageUrl(mine: true, page: 1),
        needsSession: true,
        // The mine page is account-scoped: store it under this
        // account's partition, the same key the screen reads.
        accountId: user.id,
      );
      await _warmOne(
        api,
        user,
        api.booklistsPageUrl(mine: false, order: 'popular', page: 1),
        needsSession: false,
      );
    } catch (e) {
      _logger.debug(
        'Booklist warm-up failed',
        tag: 'BooklistWarmup',
        metadata: {'error': e.toString()},
      );
    }
  }

  /// Warm one page: skip when the in-memory cache already holds a
  /// real page for it, otherwise solve headless, persist the HTML,
  /// and bridge the clearance cookies to Dio.
  static Future<void> _warmOne(
    ZLibraryApi api,
    User user,
    String url, {
    required bool needsSession,
    String? accountId,
  }) async {
    try {
      final warm = ChallengeHtmlCache.get(url);
      if (warm != null && !WebviewChallengeSolver.isChallengeHtml(warm)) {
        return;
      }
      if (needsSession) {
        await installSessionCookies(
          userId: user.id,
          userKey: user.remixUserkey,
          pageUrl: url,
        );
      }
      final html = await WebviewChallengeSolver.fetchHtmlHeadlessOnly(url);
      if (html == null ||
          html.isEmpty ||
          WebviewChallengeSolver.isChallengeHtml(html)) {
        return;
      }
      BooklistHtmlCache.store(url, html, accountId: accountId);
      await bridgeWallCookies(api, url);
    } catch (e) {
      _logger.debug(
        'Booklist warm-up failed for page',
        tag: 'BooklistWarmup',
        metadata: {'url': url, 'error': e.toString()},
      );
    }
  }
}
