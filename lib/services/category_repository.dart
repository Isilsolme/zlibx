import 'package:olib_api_plugin/olib_api_plugin.dart';

import 'booklist_solver.dart';
import 'wall_cookie_bridge.dart';
import 'webview_challenge_solver.dart';

/// Data layer for the category browsing screens: fetching (fast Dio
/// first, the WebView solver on the browser-check wall) and parsing.
///
/// A category page (`/category/{id}`, 10 books per page, `?page=N`)
/// is plain HTML; the plugin's [ZLibraryApi.getCategoryBooks] fetches
/// and parses it with the same `<z-bookcard>` parser the booklist
/// detail page uses. Unlike the booklist repository there is no
/// persistent cache here: category pages are read-only listings, so
/// every open revalidates from the network (v1).
class CategoryRepository {
  CategoryRepository(this._api);

  final ZLibraryApi _api;

  /// One page of books in [categoryId] (page 1 = 10 books).
  Future<ApiResponse<List<Book>>> fetchBooks({
    required int categoryId,
    int page = 1,
  }) =>
      _api.getCategoryBooks(categoryId, page: page);

  /// The full URL of one category page — the solver fallback's URL
  /// (the WebView follows the bare-id redirect itself).
  String categoryPageUrl({required int categoryId, int page = 1}) =>
      _api.categoryPageUrl(categoryId, page: page);

  /// The plugin's short error for a browser-check wall (plus the older
  /// shapes a wall can surface as).
  bool isChallengeError(String? error) =>
      BooklistSolver.isChallengeError(error);

  /// Parses solver-fetched HTML into books, or null when it fails to
  /// parse. A parse failure here must not escape the load (which runs
  /// from a microtask) and leave the screen loading forever — treat a
  /// broken page like a fetch failure.
  List<Book>? parseBooks(String html, {required String baseUrl}) {
    try {
      return parseBooklistDetailBooks(html, baseUrl: baseUrl);
    } catch (_) {
      return null;
    }
  }

  /// Fetches [url] through the WebView solver and returns the real
  /// page HTML, or null when the solve failed. When [userId] and
  /// [userKey] are both given, the login session is installed into the
  /// WebView's CookieManager first. Unlike
  /// [BooklistSolver.fetchHtml] the solved page is NOT stored in the
  /// booklist HTML cache — that cache is keyed by booklist URLs and
  /// category pages do not belong in it.
  Future<String?> fetchViaSolver(
    String url, {
    String? userId,
    String? userKey,
  }) async {
    if (userId != null && userKey != null && userKey.isNotEmpty) {
      await installSessionCookies(
        userId: userId,
        userKey: userKey,
        pageUrl: url,
      );
    }
    final html = await WebviewChallengeSolver.fetchHtmlAfterChallenge(url);
    if (html == null ||
        html.isEmpty ||
        BooklistSolver.isChallengeHtml(html)) {
      return null;
    }
    await bridgeWallCookies(_api, url);
    return html;
  }
}
