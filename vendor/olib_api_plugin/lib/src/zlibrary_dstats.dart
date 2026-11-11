// Download-history domain of [ZLibraryApi]: the site's own account-wide
// "download history" page. Split out as its own mixin (same pattern as
// the other domain mixins — a part in the same library, `on
// ZLibraryApiBase`, so it can use the private HTTP helpers) because it
// is a DIFFERENT data source from the eapi downloaded list, not a
// variant of it.
//
// Why this page exists here at all (2026-11-12 user report + saved
// zh.z-library.sk 下载历史 page): the eapi
// `/eapi/user/book/downloaded` list does NOT match what the website's
// download-history page shows — records made on other devices and
// through the website are absent from the eapi list, so any client
// reading only the eapi can never show the full history. The site's
// page (`/users/dstats`) is the real per-download log: server-rendered
// HTML, one `tr.dstats-row` per download event, 50 rows per page,
// navigated with `?page=N`; its own JS does no AJAX.
part of 'zlibrary_api.dart';

/// Download-history methods for [ZLibraryApi].
mixin ZLibraryDownloadHistory on ZLibraryApiBase {
  /// One page of the site's download history (`/users/dstats?page=N`),
  /// parsed into [Book]s (id, title, `/book/{hash}/…` href and
  /// `downloadedAt`; no author/cover/extension/size — the page does not
  /// render them, overlay those from the eapi downloaded list).
  ///
  /// Newest download first (the site's own order). An empty list means
  /// the page rendered no rows — past the last page, or a genuinely
  /// empty history. Failures (wall, session gone, 404 on a mirror
  /// without the page) come back as [ApiResponse.fail] with the real
  /// cause, never as an empty list.
  Future<ApiResponse<List<Book>>> getUserDownloadHistoryPage({
    int? page,
  }) async {
    final raw = await _getWithRedirects(
      '/users/dstats',
      queryParameters: {if (page != null && page > 1) 'page': page},
    );
    if (raw.error == 'cf_blocked') {
      return ApiResponse.fail('cf_blocked', statusCode: raw.status);
    }
    final status = raw.status;
    final is2xx = status != null && status >= 200 && status < 300;
    if (!is2xx) {
      return ApiResponse.fail(
        raw.error ?? 'download history failed',
        statusCode: status,
      );
    }
    // The page is always HTML; a JSON answer means the mirror served
    // something else entirely (an API error wrapper, a redirect target
    // the follow-up converted) — fail loudly instead of parsing noise.
    final body = raw.body;
    if (body == null || body.isEmpty) {
      return ApiResponse.fail(
        raw.error ?? 'download history: empty response (HTTP $status)',
        statusCode: status,
      );
    }
    return ApiResponse.ok(parseDownloadStatsPage(body));
  }
}
