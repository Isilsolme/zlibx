// Category browsing domain of [ZLibraryApi]: books on one category
// page. A category page (`/category/{id}`, e.g. `/category/75`) is
// server-rendered HTML — 10 `<z-bookcard>` elements per page — parsed
// by the same [parseBooklistDetailBooks] the booklist detail page
// uses. Split out as a mixin in the same library, `on
// ZLibraryApiBase`, so it can use the base class's private HTTP
// helpers directly.
part of 'zlibrary_api.dart';

/// Category browsing methods for [ZLibraryApi].
mixin ZLibraryCategories on ZLibraryApiBase {
  /// Books on one page of a category, parsed from the category page's
  /// own HTML (`/category/{id}`, via [parseBooklistDetailBooks]).
  ///
  /// The bare id URL 301/302s to the slugged form
  /// (`/category/75/Film-Television--Music/`), so this goes through
  /// [_getWithRedirects] — plain [_get] does not follow redirects.
  /// Page 2+ is the same URL with `?page=N` (the page's own script
  /// reads the `page` query param). Every page is HTML: there is no
  /// JSON endpoint for category pages. The page count is not in the
  /// document (the `pagerOptions` script is not inline), so callers
  /// page until a short page arrives — 10 cards per page, a page with
  /// fewer means the last page.
  ///
  /// The category page is an HTML route, so like the booklist pages
  /// it can answer with the browser-check wall: a challenge page is
  /// reported as `HTTP 503: browser check page` (via
  /// [_looksLikeChallengePage]) so the caller can fall back to the
  /// WebView solver, exactly like the booklists screen does.
  Future<ApiResponse<List<Book>>> getCategoryBooks(
    int categoryId, {
    int page = 1,
  }) async {
    final path = page <= 1
        ? '/category/$categoryId'
        : '/category/$categoryId?page=$page';
    final raw = await _getWithRedirects(
      path,
      extraHeaders: const {'Accept': 'text/html'},
    );
    final status = raw.status;
    if (status == null || status < 200 || status >= 300) {
      return ApiResponse.fail(
        raw.error ?? 'category failed (HTTP $status)',
        statusCode: status,
      );
    }
    final html = raw.body;
    if (html == null || html.isEmpty) {
      return ApiResponse.fail(
        raw.error ?? 'category failed',
        statusCode: status,
      );
    }
    if (ZLibraryApiBase._looksLikeChallengePage(html)) {
      return ApiResponse.fail(
        'HTTP $status: browser check page',
        statusCode: status,
      );
    }
    return ApiResponse.ok(parseBooklistDetailBooks(html, baseUrl: _base));
  }

  /// The full URL of one category page — the string the app's screens
  /// use for their solver fallback (the WebView follows the bare-id
  /// redirect itself).
  String categoryPageUrl(int categoryId, {int page = 1}) {
    final path = page <= 1
        ? '/category/$categoryId'
        : '/category/$categoryId?page=$page';
    return '$_base$path';
  }
}
