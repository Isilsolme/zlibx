import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'api_response.dart';
import 'book.dart';
import 'book_comment.dart';
import 'booklist.dart';
import 'user.dart';

part 'zlibrary_auth.dart';
part 'zlibrary_search.dart';
part 'zlibrary_booklists.dart';

/// App-facing byte sink for the pending-MediaStore download flow
/// (Android 10+): the app streams bytes straight into an IS_PENDING
/// entry instead of staging a .part file. Implemented by the app's
/// PendingUriWriter; the plugin only ever calls these members, so it
/// has no dependency on app code. All engines keep their current
/// behaviour when no writer is passed.
abstract class PendingDownloadWriter {
  /// The MediaStore entry being filled (changes after [reset]).
  String get uri;

  /// Resume offset: bytes already committed (plus any buffered bytes).
  int get bytesWritten;

  /// Buffer one network chunk; may flush internally.
  Future<void> add(List<int> chunk);

  /// Commit all buffered bytes. Throws when the platform write fails.
  Future<void> flush();

  /// Delete the pending entry and all sidecars (cancel / bad content).
  Future<void> discard();

  /// Recreate the pending entry empty (server restarted the body).
  /// False when the new entry cannot be created.
  Future<bool> reset();
}

/// The server answered a download request with an HTML page (a
/// challenge / error page) instead of the file. Never resumable: the
/// destination (partial file or pending entry) is useless and must be
/// discarded, never resumed.
class DownloadHtmlException implements Exception {
  final String message;
  const DownloadHtmlException(this.message);
  @override
  String toString() => message;
}

/// Shared session and HTTP infrastructure for [ZLibraryApi] and its
/// domain mixins. Public — not library-private — on purpose:
/// [ZLibraryApi] extends this class and [ZLibraryAuth] constrains
/// on it, so a private base would put a private type in the
/// public API.
abstract class ZLibraryApiBase {
  static const String _defaultDomain = 'bookroom.lifestyle';

  final Dio _dio;
  String _domain;
  String? _userId;
  String? _userKey;

  /// Wall-clearance cookies copied from the WebView's CookieManager
  /// after a challenge solve (`__diamwall`, `cf_clearance`, ...).
  /// They ride along in the same `Cookie` header as the session, so
  /// later HTML loads pass the wall through fast Dio instead of
  /// solving again. In-memory only, like the session — a fresh solve
  /// re-bridges them. The download path strips the whole `Cookie`
  /// header for cross-host links, so these never leak to a CDN.
  final Map<String, String> _wallCookies = {};

  /// [dio] is a test seam: a caller-provided client (with a fake
  /// adapter) replaces the default one. Production code never passes it.
  ZLibraryApiBase({String? domain, Dio? dio})
    : _domain = _cleanDomain(domain ?? _defaultDomain),
      _dio = dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 60),
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
                    'Chrome/120.0 Mobile Safari/537.36',
                'Accept': 'application/json',
              },
            ),
          );

  static String _cleanDomain(String domain) {
    var d = domain.trim();
    d = d.replaceFirst(RegExp(r'^https?://'), '');
    // Drop anything that is not the host (path / query / fragment / userinfo
    // would otherwise be baked into every request URL and could smuggle a
    // different host past the caller).
    final cut = d.indexOf(RegExp(r'[/?#]'));
    if (cut >= 0) d = d.substring(0, cut);
    final at = d.lastIndexOf('@');
    if (at >= 0) d = d.substring(at + 1);
    while (d.endsWith('/')) {
      d = d.substring(0, d.length - 1);
    }
    return d;
  }

  String get _base => 'https://$_domain';

  Map<String, String> get _headers {
    final h = <String, String>{};
    final parts = <String>[];
    if (_userId != null && _userKey != null) {
      parts.add('remix_userid=$_userId');
      parts.add('remix_userkey=$_userKey');
    }
    // Wall-clearance cookies ride in the same header, so the
    // download path's cross-host Cookie strip covers them too.
    for (final entry in _wallCookies.entries) {
      parts.add('${entry.key}=${entry.value}');
    }
    if (parts.isNotEmpty) h['Cookie'] = parts.join('; ');
    return h;
  }

  // ── Low-level helpers ──────────────────────────────────────────────

  Future<_Raw> _get(
    String path, {
    Map<String, dynamic>? query,
    Map<String, String>? extraHeaders,
  }) async {
    try {
      final res = await _dio.get<String>(
        '$_base$path',
        queryParameters: query,
        options: Options(
          headers: {..._headers, ...?extraHeaders},
          responseType: ResponseType.plain,
          followRedirects: false,
        ),
      );
      return _fromResponse(res);
    } on DioException catch (e) {
      return _fromError(e);
    }
  }

  Future<_Raw> _postForm(
    String path,
    Map<String, dynamic> fields,
  ) async {
    try {
      final res = await _dio.post<String>(
        '$_base$path',
        data: _encodeForm(fields),
        options: Options(
          headers: _headers,
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          followRedirects: false,
        ),
      );
      return _fromResponse(res);
    } on DioException catch (e) {
      return _fromError(e);
    }
  }

  /// POST a raw string body as `text/plain`, following redirects by
  /// hand — same pattern as the download path (downloadBook).
  ///
  /// The site's `papi/comments/*` endpoints answer the first POST with
  /// 307 to the same URL; 307/308 are re-POSTed with the same body,
  /// 301/302/303 are followed as GET (browser behaviour). The session
  /// Cookie is only sent to our own host: a hop to another host drops
  /// it (Dio's automatic following would re-send it to whatever host
  /// a 302 points at).
  ///
  /// Redirect failures (no Location, non-https target, too many hops,
  /// unparsable Location) return an error [_Raw] — never throw: the
  /// three callers only handle `ApiResponse.fail`, they do not catch
  /// [StateError].
  Future<_Raw> _postText(String path, String body) async {
    var url = '$_base$path';
    var headers = Map<String, String>.from(_headers);
    if (Uri.parse(url).host != Uri.parse(_base).host) {
      headers.remove('Cookie');
    }
    var isPost = true;
    var lastStatus = 0;
    for (var hop = 0; hop < 5; hop++) {
      try {
        final Response<String> res;
        if (isPost) {
          res = await _dio.post<String>(
            url,
            data: body,
            options: Options(
              headers: headers,
              contentType: 'text/plain;charset=UTF-8',
              responseType: ResponseType.plain,
              followRedirects: false,
              validateStatus: (status) => status != null && status < 400,
            ),
          );
        } else {
          res = await _dio.get<String>(
            url,
            options: Options(
              headers: headers,
              responseType: ResponseType.plain,
              followRedirects: false,
              validateStatus: (status) => status != null && status < 400,
            ),
          );
        }
        final code = res.statusCode ?? 0;
        lastStatus = code;
        if (code != 301 &&
            code != 302 &&
            code != 303 &&
            code != 307 &&
            code != 308) {
          return _fromResponse(res);
        }
        final location = res.headers.value(HttpHeaders.locationHeader);
        if (location == null || location.isEmpty) {
          return _Raw(status: code, error: 'redirect without location');
        }
        final Uri next;
        try {
          next = Uri.parse(url).resolveUri(Uri.parse(location));
        } on FormatException {
          return _Raw(status: code, error: 'redirect to invalid URL');
        }
        if (next.scheme != 'https') {
          return _Raw(status: code, error: 'redirect to non-https URL');
        }
        url = next.toString();
        if (next.host != Uri.parse(_base).host) {
          headers = Map<String, String>.from(headers)..remove('Cookie');
        }
        // 301/302/303 turn the follow-up into a GET; 307/308 keep
        // the original POST (same URL, same body).
        isPost = code == 307 || code == 308;
      } on DioException catch (e) {
        return _fromError(e);
      }
    }
    return _Raw(status: lastStatus, error: 'too many redirects');
  }

  /// Form encoding with repeated keys for list values, matching how the
  /// Python eapi clients send the same parameters.
  static String _encodeForm(Map<String, dynamic> fields) {
    final parts = <String>[];
    for (final entry in fields.entries) {
      final value = entry.value;
      if (value == null) continue;
      if (value is Iterable) {
        for (final item in value) {
          parts.add(
            '${Uri.encodeQueryComponent(entry.key)}='
            '${Uri.encodeQueryComponent(item.toString())}',
          );
        }
      } else {
        parts.add(
          '${Uri.encodeQueryComponent(entry.key)}='
          '${Uri.encodeQueryComponent(value.toString())}',
        );
      }
    }
    return parts.join('&');
  }

  _Raw _fromResponse(Response<String> res) {
    final body = res.data ?? '';
    final status = res.statusCode;
    final cookies = res.headers['set-cookie'] ?? const <String>[];
    if (status == 403 && _looksLikeCloudflare(body)) {
      return _Raw(status: status, error: 'cf_blocked', cookies: cookies);
    }
    if (body.isEmpty) {
      return _Raw(
        status: status,
        error: 'empty response (HTTP $status)',
        cookies: cookies,
      );
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return _Raw(status: status, json: decoded, cookies: cookies);
      }
      return _Raw(status: status, error: 'unexpected response format');
    } on FormatException {
      if (_looksLikeCloudflare(body)) {
        return _Raw(status: status, error: 'cf_blocked');
      }
      // Not JSON — keep the raw body: the site's list pages (booklists)
      // are HTML, fetched with `Accept: text/html`. Set-Cookie is
      // forwarded too, so a session re-issued on an HTML page is not
      // silently dropped.
      return _Raw(
        status: status,
        error: 'non-JSON response (HTTP $status)',
        body: body,
        cookies: cookies,
      );
    }
  }

  _Raw _fromError(DioException e) {
    final res = e.response;
    final status = res?.statusCode;
    final body = res?.data?.toString() ?? '';
    if (status == 403 && _looksLikeCloudflare(body)) {
      return _Raw(status: status, error: 'cf_blocked');
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return _Raw(status: status, error: 'timeout: ${e.message}');
      case DioExceptionType.connectionError:
        return _Raw(status: status, error: 'connection error: ${e.message}');
      case DioExceptionType.badResponse:
        // Do NOT flatten the body away: EAPI answers failures with
        // HTTP 400 + {"success":0,"error":"..."} and the message is the
        // only thing that tells a bad request apart from bad credentials.
        // (The login dialog redacts emails/passwords before display.)
        if (body.isNotEmpty) {
          // A browser-check wall (DDoS-Guard / Cloudflare challenge
          // page) must not leak its raw HTML into error strings: the
          // booklists screen shows this text, and the full page is
          // unreadable noise there. A JSON error body never contains
          // these markers, so this runs before the JSON decode and
          // cannot swallow a real API error.
          if (_looksLikeChallengePage(body)) {
            return _Raw(
              status: status,
              error: 'HTTP $status: browser check page',
            );
          }
          try {
            final decoded = jsonDecode(body);
            if (decoded is Map<String, dynamic>) {
              final msg = (decoded['error'] ?? decoded['message'])
                  ?.toString()
                  .trim();
              if (msg != null && msg.isNotEmpty) {
                // Server error texts carry HTML markup (e.g. the
                // "Some errors occured" 500 wraps its identifier in
                // <b>…</b><br>); strip it here, at the source, so no
                // caller can show raw tags in a toast or dialog. This
                // is the path the booklist remove/delete 500s take —
                // the JSON success:0 branch already strips, this one
                // did not.
                return _Raw(status: status, error: _plainError(msg, msg));
              }
            }
          } on FormatException {
            // Not JSON: fall through to the truncated body below.
          }
          final snippet =
              body.length > 200 ? '${body.substring(0, 200)}…' : body;
          return _Raw(
            status: status,
            error: _plainError('HTTP $status: $snippet', 'HTTP $status'),
          );
        }
        return _Raw(status: status, error: 'HTTP $status');
      case DioExceptionType.cancel:
        return _Raw(status: status, error: 'cancelled');
      default:
        return _Raw(status: status, error: e.message ?? e.toString());
    }
  }

  static bool _looksLikeCloudflare(String body) {
    final lower = body.toLowerCase();
    return lower.contains('cloudflare') ||
        lower.contains('attention required') ||
        lower.contains('cf-challenge');
  }

  /// Markers of a DDoS-Guard / Cloudflare browser-check page (the
  /// mirror answers HTML page routes with HTTP 503 + this page when it
  /// walls Dio). Checked against the raw error body in [_fromError] so
  /// the challenge HTML never reaches the UI as an error string.
  static bool _looksLikeChallengePage(String body) {
    final lower = body.toLowerCase();
    return lower.contains('checking your browser') ||
        lower.contains('ddos-guard') ||
        lower.contains('cf-challenge') ||
        lower.contains('just a moment') ||
        lower.contains('attention required');
  }

  /// eapi success is `success: 1` (sometimes `true`); some list endpoints
  /// omit the flag and just return the payload, which also counts.
  static bool _isSuccess(Map<String, dynamic> json) {
    final s = json['success'];
    if (s == null) return true;
    if (s is bool) return s;
    if (s is num) return s != 0;
    return s.toString() == '1' || s.toString().toLowerCase() == 'true';
  }

  /// The eapi answers `{"success":0,"error":"Invalid hash"}` when the
  /// hash is not the one it issued for the book. The webpage short hash
  /// (the `/book/{hash}/...` link) and the card `termshash` are both
  /// rejected — only the hash from an eapi response works. Booklist,
  /// profile and shared books carry only the short hash, so callers
  /// that hit this error resolve the real one with resolveEapiHash.
  static bool _isInvalidHashError(String? error) =>
      error != null && error.toLowerCase().contains('invalid hash');

  static Map<String, dynamic>? _userJson(Map<String, dynamic> json) {
    for (final key in const ['user', 'data', 'profile']) {
      final v = json[key];
      if (v is Map<String, dynamic>) return v;
    }
    return null;
  }

  /// The site's JSON error strings sometimes carry HTML markup; toasts
  /// show it raw, so strip tags here. A line break becomes a space
  /// first so words don't run together.
  static String _plainError(String? value, String fallback) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return fallback;
    return text
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .trim();
  }
}

/// Z-Library client, rewritten from the call sites in olib-mobile.
///
/// Session model (matches what the app assumes):
/// - Auth is the `remix_userid` / `remix_userkey` pair, sent as a Cookie
///   header on every request. [login] learns the pair from the login
///   response (Set-Cookie headers and/or the user object);
///   [loginWithToken] installs a stored pair and re-validates it against
///   `/eapi/user/profile` directly, exactly as the app's auth comment says.
/// - [setDomain] only switches the base host; cookies are re-issued on the
///   new host by the app's reverify flow ([loginWithToken]).
///
/// Endpoint status (see README.md for the full table):
/// - Verified pattern from independent public eapi clients: login, profile,
///   search, book info, file link, saved, unsave, downloaded.
/// - Plausible by the same naming pattern, NOT yet verified against a live
///   account: most_popular, recommended, recently, similar, save,
///   send_code, verify_code. Those methods fall back or fail loudly rather
///   than silently returning wrong data; see their doc comments.

class ZLibraryApi extends ZLibraryApiBase with ZLibraryAuth, ZLibrarySearch, ZLibraryBooklists {
  ZLibraryApi({super.domain, super.dio});

  String get domain => _domain;

  /// Switch the mirror host. Accepts a bare host or a full URL.
  void setDomain(String domain) {
    _domain = ZLibraryApiBase._cleanDomain(domain);
  }

  // ── Download ───────────────────────────────────────────────────────

  /// Resolve the file link via `/eapi/book/{id}/{hash}/file` and stream
  /// the file to [savePath]. Throws on failure (the app catches it and
  /// re-checks the download quota via [getProfile]).
  ///
  /// Link safety: an absolute link must be `https`; anything else is
  /// refused outright. The session Cookie is only sent to our own domain —
  /// a cross-domain link (e.g. a storage CDN) is fetched without it, and
  /// redirects are followed manually for the same reason (Dio would
  /// re-send the Cookie header to whatever host a 302 points at).
  ///
  /// `onProgress` receives `(received, total)`; `cancelToken` is the
  /// caller's Dio token (the app checks `isCancelled` itself).
  ///
  /// [title] is the book title, used only when the stored hash turns
  /// out to be a webpage short hash: the file endpoint rejects it
  /// with "Invalid hash", and the real hash is then resolved with
  /// [resolveEapiHash] (see [getBookInfo]).
  Future<void> downloadBook(
    String bookId,
    String hash,
    String savePath, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
    String? title,
    PendingDownloadWriter? pendingWriter,
  }) async {
    var link = await _resolveDownloadLink(bookId, hash, title: title);
    var headers = Map<String, String>.from(_headers);
    if (Uri.parse(link).host != Uri.parse(_base).host) {
      headers.remove('Cookie');
    }
    for (var hop = 0; hop < 5; hop++) {
      final res = await _downloadOnce(
        link,
        savePath,
        headers,
        onProgress: onProgress,
        cancelToken: cancelToken,
        pendingWriter: pendingWriter,
      );
      final code = res.statusCode ?? 0;
      if (code != 301 &&
          code != 302 &&
          code != 303 &&
          code != 307 &&
          code != 308) {
        return;
      }
      final location = res.headers.value(HttpHeaders.locationHeader);
      if (location == null || location.isEmpty) {
        throw StateError('download redirect without location');
      }
      final next = Uri.parse(link).resolveUri(Uri.parse(location));
      if (next.scheme != 'https') {
        throw StateError('download redirect to non-https URL');
      }
      link = next.toString();
      if (next.host != Uri.parse(_base).host) {
        headers = Map<String, String>.from(headers)..remove('Cookie');
      }
    }
    throw StateError('too many download redirects');
  }

  /// Download one hop of [link] into [savePath], resuming from the bytes
  /// already on disk when the server honours Range.
  ///
  /// A 3xx writes nothing (the caller follows the Location); a 200
  /// restarts the file from zero (the server ignored Range); a 206
  /// appends. A 416 (our partial file is longer than the server's file)
  /// truncates and restarts once. Progress reports the true position
  /// (resumed bytes + bytes received in this request) against the full
  /// size, so a resumed download does not restart the progress bar.
  Future<Response<ResponseBody>> _downloadOnce(
    String link,
    String savePath,
    Map<String, String> headers, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
    PendingDownloadWriter? pendingWriter,
  }) async {
    final file = File(savePath);
    var start = pendingWriter != null
        ? pendingWriter.bytesWritten
        : await file.exists()
            ? await file.length()
            : 0;
    final reqHeaders = Map<String, String>.from(headers);
    if (start > 0) reqHeaders['Range'] = 'bytes=$start-';
    final res = await _dio.get<ResponseBody>(
      link,
      options: Options(
        headers: reqHeaders,
        responseType: ResponseType.stream,
        receiveTimeout: const Duration(seconds: 300),
        followRedirects: false,
        validateStatus: (status) =>
            status != null && (status < 400 || (status == 416 && start > 0)),
      ),
      cancelToken: cancelToken,
    );
    final code = res.statusCode ?? 0;
    if (code >= 300 && code < 400) {
      // Redirect body is empty; drain it so the connection is released.
      await res.data?.stream.drain<void>();
      return res;
    }
    if (code == 416 && start > 0) {
      await res.data?.stream.drain<void>();
      if (pendingWriter != null) {
        // Recreate the pending entry empty; the recursive call then
        // restarts with start == 0 and no Range header.
        if (!await pendingWriter.reset()) {
          throw StateError('cannot restart the pending MediaStore entry');
        }
      } else {
        await file.writeAsBytes(const []);
      }
      return _downloadOnce(
        link,
        savePath,
        headers,
        onProgress: onProgress,
        cancelToken: cancelToken,
        pendingWriter: pendingWriter,
      );
    }
    final contentLength = int.tryParse(
          res.headers.value(HttpHeaders.contentLengthHeader) ?? '',
        ) ??
        -1;
    final resumed = code == 206 && start > 0;
    final total = resumed ? start + contentLength : contentLength;

    // An HTML answer to a file request is a challenge/error page, not a
    // book: saving it would produce a tiny, "successfully downloaded"
    // corrupted file. Reject before anything is written.
    final contentType =
        res.headers.value(HttpHeaders.contentTypeHeader) ?? '';
    if (contentType.toLowerCase().contains('text/html')) {
      await res.data?.stream.drain<void>();
      throw DownloadHtmlException(
        'download answered an HTML page '
        '(HTTP $code, content-type $contentType) — the mirror is likely '
        'serving a challenge or error page instead of the file',
      );
    }

    // With a pending writer there is no file sink at all; bytes go
    // through the writer's buffered channel. When the server answered
    // 200 to a resume request (restarting the body), the pending entry
    // must be recreated — appending would corrupt the file.
    IOSink? sink;
    var received = resumed ? start : 0;
    if (pendingWriter == null) {
      sink = file.openWrite(
        mode: resumed ? FileMode.append : FileMode.write,
      );
    } else if (!resumed && start > 0) {
      if (!await pendingWriter.reset()) {
        throw StateError('cannot restart the pending MediaStore entry');
      }
      received = 0;
    }
    try {
      await for (final chunk in res.data!.stream) {
        if (sink != null) {
          sink.add(chunk);
        } else {
          await pendingWriter!.add(chunk);
        }
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } finally {
      await sink?.close();
    }
    // Length check: a stream that ends early (connection dropped and
    // silently closed by a proxy, truncated CDN answer) must not count
    // as a finished download.
    if (total > 0 && received < total) {
      throw StateError(
        'download truncated: received $received of $total bytes',
      );
    }
    return res;
  }

  Future<String> _resolveDownloadLink(
    String bookId,
    String hash, {
    String? title,
  }) async {
    try {
      return await _fetchDownloadLink(bookId, hash);
    } on StateError catch (e) {
      // Same short-hash trap as [getBookInfo]: the file endpoint
      // rejects a webpage short hash with "Invalid hash". Resolve the
      // real hash once and retry; anything else is rethrown unchanged.
      if (title != null &&
          title.isNotEmpty &&
          ZLibraryApiBase._isInvalidHashError(e.message.toString())) {
        final resolved = await resolveEapiHash(bookId, title);
        if (resolved != null && resolved != hash) {
          return _fetchDownloadLink(bookId, resolved);
        }
      }
      rethrow;
    }
  }

  Future<String> _fetchDownloadLink(String bookId, String hash) async {
    final path = '/eapi/book/$bookId/$hash/file';
    try {
      final res = await _dio.get<String>(
        '$_base$path',
        options: Options(
          headers: _headers,
          responseType: ResponseType.plain,
          followRedirects: false,
        ),
      );
      final body = res.data ?? '';
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          final link = _findLink(decoded);
          if (link != null && link.isNotEmpty) {
            final uri = Uri.tryParse(link);
            if (uri != null && uri.hasScheme && uri.scheme != 'https') {
              throw StateError('download link is not https');
            }
            return link.startsWith('/') ? '$_base$link' : link;
          }
          final err = (decoded['error'] ?? decoded['message'])?.toString();
          throw StateError(err ?? 'no download link in file response');
        }
      } on FormatException {
        // Not JSON: the endpoint itself streams the file — but only if
        // the payload really is a binary/ebook response. An HTML answer
        // is a wall or error page: treating it as a "file stream" makes
        // downloadBook fetch the same page a second time and save the
        // HTML as the book (and this request already pulled the whole
        // body into memory for nothing).
        final contentType =
            res.headers.value(HttpHeaders.contentTypeHeader) ?? '';
        if (res.statusCode == 200 &&
            !contentType.toLowerCase().contains('text/html')) {
          return '$_base$path';
        }
        throw StateError(
          'file endpoint answered HTTP ${res.statusCode} '
          '(${contentType.isEmpty ? 'no content-type' : contentType}) '
          'instead of JSON or a file stream',
        );
      }
      throw StateError('no download link in file response');
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      throw StateError(_fromError(
        e,
      ).error ?? 'download link lookup failed');
    }
  }

  static String? _findLink(Map<String, dynamic> json) {
    for (final key in const [
      'downloadLink',
      'download_url',
      'downloadUrl',
      'url',
      'link',
      'file',
    ]) {
      final v = json[key];
      if (v is String && v.isNotEmpty) return v;
      if (v is Map<String, dynamic>) {
        final nested = _findLink(v);
        if (nested != null) return nested;
      }
    }
    final data = json['data'];
    if (data is Map<String, dynamic>) return _findLink(data);
    return null;
  }
}

class _Raw {
  final int? status;
  final Map<String, dynamic>? json;
  final String? error;
  final List<String> cookies;

  /// Raw response body, only filled when the response was not JSON
  /// (see [_fromResponse]) — the HTML list pages
  /// (fetched with `Accept: text/html`).
  final String? body;

  const _Raw({
    this.status,
    this.json,
    this.error,
    this.cookies = const <String>[],
    this.body,
  });
}

