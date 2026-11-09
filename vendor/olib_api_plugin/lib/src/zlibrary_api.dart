import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'api_response.dart';
import 'book.dart';
import 'book_comment.dart';
import 'booklist.dart';
import 'user.dart';

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
class ZLibraryApi {
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

  /// Called with the raw HTML of every booklist page the plugin loads
  /// successfully over Dio (list pages, profile page, detail page 1).
  /// The app registers a handler that persists it for its
  /// stale-while-revalidate cache; the plugin itself never stores
  /// anything. The URL is the page's canonical URL (the same string
  /// the app's screens use for their solver and cache keys), never
  /// the raw request URL. Null means no handler.
  void Function(String url, String html)? onBooklistHtmlLoaded;

  /// [dio] is a test seam: a caller-provided client (with a fake
  /// adapter) replaces the default one. Production code never passes it.
  ZLibraryApi({String? domain, Dio? dio})
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

  String get domain => _domain;

  /// Switch the mirror host. Accepts a bare host or a full URL.
  void setDomain(String domain) {
    _domain = _cleanDomain(domain);
  }

  /// Drop the in-memory session so the Cookie header is no longer sent.
  /// Call before switching to a host that is not trusted; trusted hosts
  /// re-issue the session explicitly via [loginWithToken].
  void clearSession() {
    _userId = null;
    _userKey = null;
    _wallCookies.clear();
  }

  /// Remember wall-clearance cookies the WebView earned by passing a
  /// browser check (see `wall_cookie_bridge.dart` in the app). They
  /// are appended to the `Cookie` header on every request to our own
  /// mirror, so the next HTML load skips the solver. Session cookies
  /// are ignored here — the plugin already sends those from its own
  /// session. Empty values are dropped. Merging by name keeps a newer
  /// solve's value while preserving cookies from an earlier one.
  void setWallCookies(Map<String, String> cookies) {
    for (final entry in cookies.entries) {
      final name = entry.key.trim();
      final value = entry.value.trim();
      if (name.isEmpty ||
          value.isEmpty ||
          name == 'remix_userid' ||
          name == 'remix_userkey') {
        continue;
      }
      _wallCookies[name] = value;
    }
  }

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

  /// One raw JSON-ish response. `json` is null when the server did not
  /// return parseable JSON (HTML wall, empty body, ...).
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
  /// hand — same pattern as the download path ([downloadBook]).
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

  /// DELETE with no request body, following redirects by hand — same
  /// pattern as [_postText]: 307/308 are re-sent as DELETE, 301/302/303
  /// are followed as GET (browser behaviour). The session Cookie is
  /// only sent to our own host: a hop to another host drops it.
  ///
  /// Redirect failures (no Location, non-https target, too many hops,
  /// unparsable Location) return an error [_Raw] — never throw: the
  /// caller only handles `ApiResponse.fail`, it does not catch
  /// [StateError].
  Future<_Raw> _delete(String path) async {
    var url = '$_base$path';
    var headers = Map<String, String>.from(_headers);
    if (Uri.parse(url).host != Uri.parse(_base).host) {
      headers.remove('Cookie');
    }
    var isDelete = true;
    var lastStatus = 0;
    for (var hop = 0; hop < 5; hop++) {
      try {
        final Response<String> res;
        if (isDelete) {
          res = await _dio.delete<String>(
            url,
            options: Options(
              headers: headers,
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
        // the original DELETE.
        isDelete = code == 307 || code == 308;
      } on DioException catch (e) {
        return _fromError(e);
      }
    }
    return _Raw(status: lastStatus, error: 'too many redirects');
  }

  /// GET, following redirects by hand — same pattern as [_postText].
  ///
  /// The site's `papi/booklist/*` write endpoints answer the first GET
  /// with 307 to the same URL (the DDoS-Guard challenge sets a cookie
  /// and redirects); 307/308 are re-sent as GET, 301/302/303 are
  /// followed as GET (browser behaviour). The session Cookie is only
  /// sent to our own host: a hop to another host drops it (Dio's
  /// automatic following would re-send it to whatever host a 302
  /// points at).
  ///
  /// Redirect failures (no Location, non-https target, too many hops,
  /// unparsable Location) return an error [_Raw] — never throw: the
  /// callers only handle `ApiResponse.fail`, they do not catch
  /// [StateError].
  Future<_Raw> _getWithRedirects(String path) async {
    var url = '$_base$path';
    var headers = Map<String, String>.from(_headers);
    if (Uri.parse(url).host != Uri.parse(_base).host) {
      headers.remove('Cookie');
    }
    var lastStatus = 0;
    for (var hop = 0; hop < 5; hop++) {
      try {
        final res = await _dio.get<String>(
          url,
          options: Options(
            headers: headers,
            responseType: ResponseType.plain,
            followRedirects: false,
            validateStatus: (status) => status != null && status < 400,
          ),
        );
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
                return _Raw(status: status, error: msg);
              }
            }
          } on FormatException {
            // Not JSON: fall through to the truncated body below.
          }
          final snippet =
              body.length > 200 ? '${body.substring(0, 200)}…' : body;
          return _Raw(status: status, error: 'HTTP $status: $snippet');
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
  /// that hit this error resolve the real one with [resolveEapiHash].
  static bool _isInvalidHashError(String? error) =>
      error != null && error.toLowerCase().contains('invalid hash');

  static Map<String, dynamic>? _metaOf(Map<String, dynamic> json) {
    final pagination = json['pagination'];
    if (pagination is Map<String, dynamic>) return pagination;
    final meta = json['meta'];
    if (meta is Map<String, dynamic>) return meta;
    return null;
  }

  static List<Book> _booksOf(Map<String, dynamic> json) {
    final raw = json['books'] ?? json['data'] ?? json['results'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(Book.fromJson)
        .toList();
  }

  static Map<String, dynamic>? _userJson(Map<String, dynamic> json) {
    for (final key in const ['user', 'data', 'profile']) {
      final v = json[key];
      if (v is Map<String, dynamic>) return v;
    }
    return null;
  }

  void _learnSession(Map<String, dynamic> json, List<String> setCookie) {
    // From Set-Cookie headers first (the server's own session values).
    for (final cookie in setCookie) {
      for (final part in cookie.split(';')) {
        final trimmed = part.trim();
        final eq = trimmed.indexOf('=');
        // Values may legitimately contain '=' (base64 padding): split on
        // the FIRST '=' only, not every one. An empty value is not a
        // session — adopting it would send `remix_userkey=` (empty) on
        // every later request.
        if (eq <= 0) continue;
        final name = trimmed.substring(0, eq);
        final value = trimmed.substring(eq + 1);
        if (value.isEmpty) continue;
        if (name == 'remix_userid') _userId = value;
        if (name == 'remix_userkey') _userKey = value;
      }
    }
    // Then from the user object, which carries the same pair.
    final userJson = _userJson(json);
    if (userJson != null) {
      final id = userJson['id']?.toString();
      final key = (userJson['remixUserkey'] ?? userJson['remix_userkey'])
          ?.toString();
      if (id != null && id.isNotEmpty) _userId = id;
      if (key != null && key.isNotEmpty) _userKey = key;
    }
  }

  // ── Auth ───────────────────────────────────────────────────────────

  /// Website-login fields, sent alongside email/password on the eapi
  /// login call. The eapi clients that work against z-lib's own domains
  /// send only email+password, but the community mirrors in this app's
  /// line list answered that shape with HTTP 400 on every line while the
  /// original app logs in fine — so the mirrors' login handler appears
  /// to want the website login's field set. EAPI handlers ignore unknown
  /// fields, so including them costs nothing where email+password alone
  /// already works.
  static const Map<String, String> _loginExtraFields = {
    'isModal': 'true',
    'site_mode': 'books',
    'action': 'login',
    'isSingleLogin': '1',
    'redirectUrl': '',
    'gg_json_mode': '1',
  };

  Future<ApiResponse<User>> login(String email, String password) async {
    final fields = <String, dynamic>{
      'email': email,
      'password': password,
      ..._loginExtraFields,
    };
    final raw = await _postForm('/eapi/user/login', fields);
    if (raw.json != null && _isSuccess(raw.json!)) {
      return _finishLogin(raw.json!, raw.cookies);
    }
    // EAPI login did not succeed. Fall back to the website login RPC on
    // the same mirror: the original app logs in on these lines, and the
    // website login is the other shape a mirror's login handler may
    // expect. If rpc.php is not served here either, the original eapi
    // error is reported, not the fallback's.
    //
    // A structured eapi rejection (an explicit error/message field, e.g.
    // "wrong email or password") is a definitive business error: the same
    // credentials will be rejected by /rpc.php too, and resubmitting them
    // only doubles the mirror's lock-out risk. Fall back only when the
    // eapi answer looks like a protocol mismatch (no usable error text).
    // (The null check must be the direct `if` condition: Dart only
    // promotes locals on a direct test, not via a boolean variable.)
    final eapiErrorText =
        (raw.json?['error'] ?? raw.json?['message'])?.toString().trim();
    if (eapiErrorText != null && eapiErrorText.isNotEmpty) {
      return ApiResponse.fail(eapiErrorText, statusCode: raw.status);
    }
    final rpc = await _postForm('/rpc.php', fields);
    if (rpc.json != null) {
      final rpcJson = rpc.json!;
      final validationError = rpcJson['validationError']?.toString().trim();
      if (validationError != null && validationError.isNotEmpty) {
        return ApiResponse.fail(validationError, statusCode: rpc.status);
      }
      // Compare against the session that was installed BEFORE this call:
      // if _learnSession learned nothing, a pair left over from a previous
      // account would still make `_userId != null && _userKey != null`
      // true, and the profile fetch would "successfully" log the previous
      // account in with this account's password.
      final prevUserId = _userId;
      final prevUserKey = _userKey;
      _learnSession(rpcJson, rpc.cookies);
      final learnedNewSession = (_userId != null && _userId != prevUserId) ||
          (_userKey != null && _userKey != prevUserKey);
      if (learnedNewSession && _userId != null && _userKey != null) {
        final profile = await getProfile();
        if (profile.success && profile.data != null) return profile;
        return ApiResponse.fail(
          profile.error ?? 'login succeeded but no user data',
          statusCode: profile.statusCode,
        );
      }
      if (_userJson(rpcJson) != null) {
        return _finishLogin(rpcJson, rpc.cookies);
      }
    }
    if (raw.json != null) {
      return ApiResponse.fail(
        (raw.json!['error'] ?? raw.json!['message'])?.toString() ??
            'login failed',
        statusCode: raw.status,
      );
    }
    return ApiResponse.fail(raw.error ?? 'login failed',
        statusCode: raw.status);
  }

  /// The user object in login/profile payloads does not always carry the
  /// session key — it usually arrives via Set-Cookie instead. But the app
  /// persists `user.remixUserkey` as its stored credential and hands it to
  /// the reader WebView, so a User with an empty key silently breaks both.
  /// Fill it from the session this layer already learned, when available.
  User _withSessionKey(User user) {
    if (user.remixUserkey.isNotEmpty) return user;
    final key = _userKey;
    if (key == null || key.isEmpty) return user;
    return User(
      id: user.id,
      email: user.email,
      name: user.name,
      remixUserkey: key,
      downloadsLeft: user.downloadsLeft,
    );
  }

  /// Shared tail of a successful login: learn the session pair from
  /// Set-Cookie headers and/or the user object; if the payload has no
  /// user object, a profile fetch fills it in.
  Future<ApiResponse<User>> _finishLogin(
    Map<String, dynamic> json,
    List<String> cookies,
  ) async {
    _learnSession(json, cookies);
    final userJson = _userJson(json);
    if (userJson == null) {
      final profile = await getProfile();
      if (profile.success && profile.data != null) return profile;
      return ApiResponse.fail(
        profile.error ?? 'login succeeded but no user data',
        statusCode: profile.statusCode,
      );
    }
    final user = User.fromJson(userJson);
    _userId ??= user.id.isNotEmpty ? user.id : null;
    _userKey ??= user.remixUserkey.isNotEmpty ? user.remixUserkey : null;
    return ApiResponse.ok(_withSessionKey(user));
  }

  /// Install a stored `remix_userid` / `remix_userkey` pair and validate
  /// it against `/eapi/user/profile`. This is what the app calls on boot
  /// and after a domain switch.
  Future<ApiResponse<User>> loginWithToken(
    String userId,
    String userKey,
  ) async {
    _userId = userId;
    _userKey = userKey;
    final profile = await getProfile();
    if (!profile.success) {
      // Do not leave an unvalidated (possibly stale or rejected) pair
      // installed: every later request would keep sending its cookies,
      // and a subsequent login()'s rpc fallback would mistake the stale
      // pair for a successful login of the wrong account.
      _userId = null;
      _userKey = null;
    }
    return profile;
  }

  /// Registration step 1: ask the server to send a verification code.
  /// Endpoint spelling is inferred, not verified against a live account.
  Future<ApiResponse<void>> sendCode(
    String email,
    String password,
    String name,
  ) async {
    final raw = await _postForm('/eapi/user/send_code', {
      'email': email,
      'password': password,
      'name': name,
    });
    if (raw.json == null) {
      return ApiResponse.fail(raw.error ?? 'send code failed',
          statusCode: raw.status);
    }
    if (!_isSuccess(raw.json!)) {
      return ApiResponse.fail(
        (raw.json!['error'] ?? raw.json!['message'])?.toString() ??
            'send code failed',
        statusCode: raw.status,
      );
    }
    return ApiResponse.ok(null);
  }

  /// Registration step 2: verify the code. The app logs in separately
  /// afterwards, so this only reports success/failure.
  Future<ApiResponse<void>> verifyCode(
    String email,
    String password,
    String name,
    String code,
  ) async {
    final raw = await _postForm('/eapi/user/verify_code', {
      'email': email,
      'password': password,
      'name': name,
      'code': code,
    });
    if (raw.json == null) {
      return ApiResponse.fail(raw.error ?? 'verify code failed',
          statusCode: raw.status);
    }
    if (!_isSuccess(raw.json!)) {
      return ApiResponse.fail(
        (raw.json!['error'] ?? raw.json!['message'])?.toString() ??
            'verify code failed',
        statusCode: raw.status,
      );
    }
    return ApiResponse.ok(null);
  }

  Future<ApiResponse<User>> getProfile() async {
    final raw = await _get('/eapi/user/profile');
    if (raw.json == null) {
      return ApiResponse.fail(raw.error ?? 'profile failed',
          statusCode: raw.status);
    }
    final json = raw.json!;
    if (!_isSuccess(json)) {
      return ApiResponse.fail(
        (json['error'] ?? json['message'])?.toString() ?? 'profile failed',
        statusCode: raw.status,
      );
    }
    final userJson = _userJson(json);
    if (userJson == null) {
      return ApiResponse.fail('profile response had no user',
          statusCode: raw.status);
    }
    return ApiResponse.ok(_withSessionKey(User.fromJson(userJson)));
  }

  // ── Search & lists ─────────────────────────────────────────────────

  Future<ApiResponse<List<Book>>> search({
    String? message,
    int? yearFrom,
    int? yearTo,
    List<String>? languages,
    List<String>? extensions,
    String? order,
    int? page,
    int? limit,
  }) async {
    final raw = await _postForm('/eapi/book/search', {
      if (message != null) 'message': message,
      if (yearFrom != null) 'yearFrom': yearFrom,
      if (yearTo != null) 'yearTo': yearTo,
      if (languages != null) 'languages': languages,
      if (extensions != null) 'extensions': extensions,
      if (order != null) 'order': order,
      if (page != null) 'page': page,
      if (limit != null) 'limit': limit,
    });
    if (raw.json == null) {
      return ApiResponse.fail(raw.error ?? 'search failed',
          statusCode: raw.status);
    }
    if (!_isSuccess(raw.json!)) {
      return ApiResponse.fail(
        (raw.json!['error'] ?? raw.json!['message'])?.toString() ??
            'search failed',
        statusCode: raw.status,
      );
    }
    return ApiResponse.ok(_booksOf(raw.json!), meta: _metaOf(raw.json!));
  }

  /// Full detail for one book. [hashId] is the eapi hash from a search
  /// response; a webpage short hash (from booklist/profile HTML, or a
  /// shared-book link) is rejected with "Invalid hash". When [title]
  /// is given and the first call fails exactly that way, the real hash
  /// is resolved with [resolveEapiHash] and the call is retried once.
  /// Any other failure is returned unchanged, and the fast path — a
  /// search-sourced book with the right hash — costs no extra call.
  Future<ApiResponse<Book>> getBookInfo(
    String bookId,
    String hashId, {
    String? title,
  }) async {
    final response = await _fetchBookInfo(bookId, hashId);
    if (response.success) return response;
    if (title != null &&
        title.isNotEmpty &&
        _isInvalidHashError(response.error)) {
      final resolved = await resolveEapiHash(bookId, title);
      if (resolved != null && resolved != hashId) {
        return _fetchBookInfo(bookId, resolved);
      }
    }
    return response;
  }

  /// Resolve the real eapi hash for a book whose stored hash is a
  /// webpage short hash: search by title and take the hash of the
  /// result with the same numeric id. Returns null when the search
  /// fails or no result matches. The search response is the only
  /// place the eapi hash appears — booklist/profile HTML and the
  /// get-books JSON carry only the short URL hash.
  Future<String?> resolveEapiHash(String bookId, String title) async {
    final res = await search(message: title, limit: 20);
    if (!res.success || res.data == null) return null;
    for (final book in res.data!) {
      if (book.id.toString() == bookId &&
          book.hash != null &&
          book.hash!.isNotEmpty) {
        return book.hash;
      }
    }
    return null;
  }

  Future<ApiResponse<Book>> _fetchBookInfo(
    String bookId,
    String hashId,
  ) async {
    final raw = await _get('/eapi/book/$bookId/$hashId');
    if (raw.json == null) {
      return ApiResponse.fail(raw.error ?? 'book info failed',
          statusCode: raw.status);
    }
    final json = raw.json!;
    if (!_isSuccess(json)) {
      return ApiResponse.fail(
        (json['error'] ?? json['message'])?.toString() ?? 'book info failed',
        statusCode: raw.status,
      );
    }
    final bookJson = json['book'];
    if (bookJson is Map<String, dynamic>) {
      return ApiResponse.ok(Book.fromJson(bookJson));
    }
    // Some endpoints return the book fields at the top level.
    if (json['title'] != null) {
      return ApiResponse.ok(Book.fromJson(json));
    }
    return ApiResponse.fail('book info response had no book',
        statusCode: raw.status);
  }

  /// Homepage "most popular". Primary path follows the eapi naming
  /// pattern; if the server 404s it, rejects it, or returns an empty
  /// list, fall back to a popularity-ordered search so the home list
  /// still works. (The community mirrors answer this endpoint with
  /// success:0 / an empty payload instead of 404, so a 404-only
  /// fallback leaves the home screen blank — device-verified 2026-11-05
  /// on the run #6 package.)
  Future<ApiResponse<List<Book>>> getMostPopular() async {
    final raw = await _get('/eapi/book/most_popular');
    // A blocked line would make the search fallback fail too — chaining
    // it only burns 2×15s more of timeouts before surfacing the same
    // "cf_blocked". The device-verified fallback for success:0/empty
    // payloads below is intentional and stays.
    if (raw.error == 'cf_blocked') {
      return ApiResponse.fail('cf_blocked', statusCode: raw.status);
    }
    if (raw.status == 404) {
      return search(order: 'popular', limit: 20);
    }
    if (raw.json == null) {
      return search(order: 'popular', limit: 20);
    }
    if (!_isSuccess(raw.json!)) {
      return search(order: 'popular', limit: 20);
    }
    final books = _booksOf(raw.json!);
    if (books.isEmpty) {
      return search(order: 'popular', limit: 20);
    }
    return ApiResponse.ok(books, meta: _metaOf(raw.json!));
  }

  /// Personalised home recommendations. Falls back to most-popular when
  /// the personalised endpoint 404s, fails, or returns an empty list:
  /// a wrong guess here must not blank the home screen (a fresh account
  /// has no history, so the endpoint legitimately returns nothing).
  Future<ApiResponse<List<Book>>> getUserRecommended() async {
    final raw = await _get('/eapi/user/recommended');
    // Same cf_blocked short-circuit as [getMostPopular].
    if (raw.error == 'cf_blocked') {
      return ApiResponse.fail('cf_blocked', statusCode: raw.status);
    }
    if (raw.status == 404) return getMostPopular();
    if (raw.json == null) return getMostPopular();
    if (!_isSuccess(raw.json!)) return getMostPopular();
    final books = _booksOf(raw.json!);
    if (books.isEmpty) return getMostPopular();
    return ApiResponse.ok(books, meta: _metaOf(raw.json!));
  }

  /// Recently added books. Falls back to a newest-ordered search on 404.
  Future<ApiResponse<List<Book>>> getRecently() async {
    final raw = await _get('/eapi/book/recently');
    // Same cf_blocked short-circuit as [getMostPopular]: the search
    // fallback cannot succeed on a blocked line either.
    if (raw.error == 'cf_blocked') {
      return ApiResponse.fail('cf_blocked', statusCode: raw.status);
    }
    if (raw.status == 404) {
      return search(order: 'newest', limit: 20);
    }
    if (raw.json == null) {
      return ApiResponse.fail(raw.error ?? 'recently failed',
          statusCode: raw.status);
    }
    if (!_isSuccess(raw.json!)) {
      return ApiResponse.fail(
        (raw.json!['error'] ?? raw.json!['message'])?.toString() ??
            'recently failed',
        statusCode: raw.status,
      );
    }
    return ApiResponse.ok(_booksOf(raw.json!), meta: _metaOf(raw.json!));
  }

  Future<ApiResponse<List<Book>>> getUserSaved({
    int? page,
    int? limit,
  }) async {
    final raw = await _get(
      '/eapi/user/book/saved',
      query: {
        if (page != null) 'page': page,
        if (limit != null) 'limit': limit,
      },
    );
    if (raw.json == null) {
      return ApiResponse.fail(raw.error ?? 'saved books failed',
          statusCode: raw.status);
    }
    if (!_isSuccess(raw.json!)) {
      return ApiResponse.fail(
        (raw.json!['error'] ?? raw.json!['message'])?.toString() ??
            'saved books failed',
        statusCode: raw.status,
      );
    }
    return ApiResponse.ok(_booksOf(raw.json!), meta: _metaOf(raw.json!));
  }

  Future<ApiResponse<List<Book>>> getUserDownloaded({
    int? limit,
  }) async {
    final raw = await _get(
      '/eapi/user/book/downloaded',
      query: {if (limit != null) 'limit': limit},
    );
    if (raw.json == null) {
      return ApiResponse.fail(raw.error ?? 'downloaded books failed',
          statusCode: raw.status);
    }
    if (!_isSuccess(raw.json!)) {
      return ApiResponse.fail(
        (raw.json!['error'] ?? raw.json!['message'])?.toString() ??
            'downloaded books failed',
        statusCode: raw.status,
      );
    }
    return ApiResponse.ok(_booksOf(raw.json!), meta: _metaOf(raw.json!));
  }

  /// Save to "My library". Mirrors the confirmed unsave path.
  Future<ApiResponse<void>> saveBook(String bookId) async {
    final raw = await _get('/eapi/user/book/$bookId/save');
    if (raw.json == null) {
      return ApiResponse.fail(raw.error ?? 'save failed',
          statusCode: raw.status);
    }
    if (!_isSuccess(raw.json!)) {
      return ApiResponse.fail(
        (raw.json!['error'] ?? raw.json!['message'])?.toString() ??
            'save failed',
        statusCode: raw.status,
      );
    }
    return ApiResponse.ok(null);
  }

  /// Confirmed path from the public eapi clients.
  Future<ApiResponse<void>> unsaveUserBook(String bookId) async {
    final raw = await _get('/eapi/user/book/$bookId/unsave');
    if (raw.json == null) {
      return ApiResponse.fail(raw.error ?? 'unsave failed',
          statusCode: raw.status);
    }
    if (!_isSuccess(raw.json!)) {
      return ApiResponse.fail(
        (raw.json!['error'] ?? raw.json!['message'])?.toString() ??
            'unsave failed',
        statusCode: raw.status,
      );
    }
    return ApiResponse.ok(null);
  }

  /// Books similar to one book. Falls back to a title search on 404.
  Future<ApiResponse<List<Book>>> similar(
    String bookId,
    String hashId,
  ) async {
    final raw = await _get('/eapi/book/$bookId/$hashId/similar');
    if (raw.status == 404) {
      final info = await getBookInfo(bookId, hashId);
      if (!info.success || info.data == null) {
        return ApiResponse.fail(
          info.error ?? 'similar failed',
          statusCode: info.statusCode,
        );
      }
      final res = await search(message: info.data!.title, limit: 20);
      if (!res.success) return res;
      final books =
          res.data!.where((b) => b.id.toString() != bookId).toList();
      return ApiResponse.ok(books, meta: res.meta);
    }
    if (raw.json == null) {
      return ApiResponse.fail(raw.error ?? 'similar failed',
          statusCode: raw.status);
    }
    if (!_isSuccess(raw.json!)) {
      return ApiResponse.fail(
        (raw.json!['error'] ?? raw.json!['message'])?.toString() ??
            'similar failed',
        statusCode: raw.status,
      );
    }
    return ApiResponse.ok(_booksOf(raw.json!), meta: _metaOf(raw.json!));
  }

  /// Book comments, view-only. The site's own `papi/` JSON API, NOT eapi:
  /// `GET /papi/comments/book/{bookId}/{page}?limit={limit}`.
  /// Confirmed by a packet capture on 2026-11-06 (zh.z-library.sk book
  /// page): `success: 1`, a `comments` array, a `commentsDisabled` flag.
  /// Auth is the same remix session cookies the eapi calls send; the
  /// endpoint needs a logged-in session. Page is 0-based; there is no
  /// total/pages field, so callers page until a short page arrives.
  Future<ApiResponse<BookCommentsPage>> getBookComments(
    String bookId, {
    int page = 0,
    int limit = 50,
  }) async {
    final raw = await _get('/papi/comments/book/$bookId/$page?limit=$limit');
    if (raw.json == null) {
      return ApiResponse.fail(raw.error ?? 'comments failed',
          statusCode: raw.status);
    }
    final json = raw.json!;
    if (!_isSuccess(json)) {
      return ApiResponse.fail(
        (json['error'] ?? json['message'])?.toString() ?? 'comments failed',
        statusCode: raw.status,
      );
    }
    if (json['commentsDisabled'] == true) {
      return ApiResponse.ok(
          const BookCommentsPage(comments: [], disabled: true));
    }
    final list = json['comments'];
    if (list is! List) {
      return ApiResponse.fail('comments response had no list',
          statusCode: raw.status);
    }
    final reactions = commentReactionsOf(json);
    return ApiResponse.ok(BookCommentsPage(
      comments: list
          .whereType<Map<String, dynamic>>()
          .map((c) => BookComment.fromJson(c, baseUrl: _base))
          .map((c) {
            final r = reactions[c.id];
            return r == null
                ? c
                : c.copyWith(likeCount: r.count, isLiked: r.liked);
          })
          .toList(),
    ));
  }

  /// The signed-in user's own posted comments, as the website shows them
  /// on the profile Comments tab:
  /// `GET /papi/comments/user/{userId}/{page}?limit={limit}`.
  /// Confirmed by a packet capture on 2026-11-06 (zh.z-library.sk
  /// profile page): `success: 1`, `comments` as a MAP keyed by comment
  /// id (not a list), `commentsTitles: {book: {...}}` with each
  /// comment's book title, plus `reactionsInfo`/`reactionsUsers`.
  /// Page is 0-based; the site fetches limit 500 for the whole
  /// collection in one go. Auth is the remix session cookies.
  Future<ApiResponse<UserCommentsPage>> getMyComments({
    int page = 0,
    int limit = 500,
  }) async {
    final userId = _userId;
    if (userId == null || userId.isEmpty) {
      return ApiResponse.fail('not logged in');
    }
    return _fetchUserCommentsPage(userId, page, limit);
  }

  /// Another user's posted comments, same endpoint as [getMyComments]
  /// but for an arbitrary user id (the id comes from a tapped
  /// comment's `user_id`). Same page/limit semantics; the viewer
  /// still needs a logged-in session (remix cookies).
  Future<ApiResponse<UserCommentsPage>> getUserComments(
    String userId, {
    int page = 0,
    int limit = 500,
  }) async {
    if (userId.isEmpty) {
      return ApiResponse.fail('missing user id');
    }
    return _fetchUserCommentsPage(userId, page, limit);
  }

  Future<ApiResponse<UserCommentsPage>> _fetchUserCommentsPage(
    String userId,
    int page,
    int limit,
  ) async {
    final raw = await _get('/papi/comments/user/$userId/$page?limit=$limit');
    if (raw.json == null) {
      return ApiResponse.fail(raw.error ?? 'my comments failed',
          statusCode: raw.status);
    }
    final json = raw.json!;
    if (!_isSuccess(json)) {
      return ApiResponse.fail(
        (json['error'] ?? json['message'])?.toString() ??
            'my comments failed',
        statusCode: raw.status,
      );
    }
    final map = json['comments'];
    if (map is! Map) {
      return ApiResponse.fail('my comments response had no map',
          statusCode: raw.status);
    }
    final reactions = commentReactionsOf(json);
    final titles = commentTitlesOf(json);
    final entries = <UserCommentEntry>[];
    for (final value in map.values) {
      if (value is! Map<String, dynamic>) continue;
      final bookId = value['object_id'] is int
          ? value['object_id'] as int
          : int.tryParse('${value['object_id']}') ?? 0;
      final comment = BookComment.fromJson(value, baseUrl: _base);
      final r = reactions[comment.id];
      entries.add(UserCommentEntry(
        comment: r == null
            ? comment
            : comment.copyWith(likeCount: r.count, isLiked: r.liked),
        bookId: bookId,
        bookTitle: titles[bookId] ?? '',
      ));
    }
    return ApiResponse.ok(UserCommentsPage(entries: entries));
  }

  /// Post a book comment, or a reply when [parentId] is set. The site's
  /// own `papi/` JSON API: `POST /papi/comments/add` with a JSON body
  /// (`hash`, `object: "book"`, `object_id` as a STRING, `text`, plus
  /// `parent_id` for replies), sent as `text/plain`. Confirmed by a
  /// packet capture on 2026-11-06: the first request answers 307 to the
  /// same URL and the follow-up returns 200
  /// `{success: 1, comment: {...}, currentUser: {...}}` — the new
  /// comment comes back in the same shape as the read list, so callers
  /// can insert it directly. Auth is the remix session cookies.
  Future<ApiResponse<BookComment>> postBookComment(
    String bookId, {
    required String text,
    String? parentId,
  }) async {
    final body = <String, dynamic>{
      'hash': '',
      'object': 'book',
      'object_id': bookId,
      'text': text,
    };
    if (parentId != null) body['parent_id'] = parentId;
    final raw = await _postText('/papi/comments/add', jsonEncode(body));
    if (raw.json == null) {
      return ApiResponse.fail(raw.error ?? 'post comment failed',
          statusCode: raw.status);
    }
    final json = raw.json!;
    if (!_isSuccess(json)) {
      return ApiResponse.fail(
        (json['error'] ?? json['message'])?.toString() ??
            'post comment failed',
        statusCode: raw.status,
      );
    }
    final comment = json['comment'];
    if (comment is! Map<String, dynamic>) {
      return ApiResponse.fail('post comment had no comment',
          statusCode: raw.status);
    }
    return ApiResponse.ok(BookComment.fromJson(comment, baseUrl: _base));
  }

  /// Like ([like] true) or unlike a comment. `POST
  /// /papi/comments/like/{commentId}/{1|0}` with an empty JSON body,
  /// confirmed by a packet capture on 2026-11-06 (same 307-to-same-URL
  /// hop as posting). The 200 answer carries the comment's new like
  /// state (`likes` + `isLiked` arrays) in the same shape as the read
  /// page's `reactionsInfo`.
  Future<ApiResponse<CommentLikeResult>> likeBookComment(
    int commentId, {
    required bool like,
  }) async {
    final raw = await _postText(
      '/papi/comments/like/$commentId/${like ? 1 : 0}',
      '{}',
    );
    if (raw.json == null) {
      return ApiResponse.fail(raw.error ?? 'like failed',
          statusCode: raw.status);
    }
    final json = raw.json!;
    if (!_isSuccess(json)) {
      return ApiResponse.fail(
        (json['error'] ?? json['message'])?.toString() ?? 'like failed',
        statusCode: raw.status,
      );
    }
    final result = CommentLikeResult.fromLikeJson(json, commentId);
    if (result == null) {
      return ApiResponse.fail('like response had no update',
          statusCode: raw.status);
    }
    return ApiResponse.ok(result);
  }

  /// Delete one of the signed-in user's own comments. `DELETE
  /// /papi/comments/delete/{commentId}` with no request body,
  /// confirmed by a packet capture on 2026-11-09 (Firefox,
  /// zh.z-library.sk): HTTP 200 with `{"success": 1}`.
  ///
  /// The capture's Payload tab was not shown, so "no body" is an
  /// assumption from the id-in-path shape and the sibling endpoints
  /// (like posts an empty JSON body); device testing will confirm it.
  Future<ApiResponse<bool>> deleteBookComment(int commentId) async {
    final raw = await _delete('/papi/comments/delete/$commentId');
    if (raw.json == null) {
      return ApiResponse.fail(raw.error ?? 'delete comment failed',
          statusCode: raw.status);
    }
    final json = raw.json!;
    if (!_isSuccess(json)) {
      return ApiResponse.fail(
        (json['error'] ?? json['message'])?.toString() ??
            'delete comment failed',
        statusCode: raw.status,
      );
    }
    return ApiResponse.ok(true);
  }

  // ── Booklists ──────────────────────────────────────────────────────

  /// Public booklists, read-only. The site's own list page
  /// (`GET /booklists?searchQuery={q}&order={order}&page={n}`) is HTML:
  /// `<z-booklist>` elements, parsed by [parseBooklistsPage].
  /// [order] is `popular` (default), `date_created` or `date_updated`.
  /// Page is 1-based. Shapes come from the public sertraline/zlibrary
  /// client (read as a shape reference only — no code copied) and are
  /// NOT yet live-verified; the list HTML may drift. Needs a logged-in
  /// session like the rest of the site's pages.
  Future<ApiResponse<BooklistsPage>> searchPublicBooklists({
    String query = '',
    String order = 'popular',
    int page = 1,
  }) async {
    return _searchBooklists(
      '/booklists',
      query: query,
      order: order,
      page: page,
    );
  }

  /// The signed-in user's own booklists, read-only
  /// (`GET /booklists/my?searchQuery={q}&page={n}`, same HTML shape as
  /// the public list). Same verification status as
  /// [searchPublicBooklists].
  Future<ApiResponse<BooklistsPage>> searchMyBooklists({
    String query = '',
    int page = 1,
  }) async {
    return _searchBooklists('/booklists/my', query: query, page: page);
  }

  /// Absolute URL of a booklist list page, for callers that fetch the
  /// HTML themselves (e.g. through the WebView challenge solver when
  /// the mirror walls Dio with a 503 browser-check page). Same path +
  /// query construction as [_searchBooklists] — the app must not
  /// rebuild it.
  String booklistsPageUrl({
    required bool mine,
    String query = '',
    String? order,
    int page = 1,
  }) {
    final uri = Uri.parse('$_base${mine ? '/booklists/my' : '/booklists'}')
        .replace(
          queryParameters: _booklistListParams(
            query: query,
            order: order,
            page: page,
          ).map((key, value) => MapEntry(key, value.toString())),
        );
    return uri.toString();
  }

  /// Query parameters of a booklist list page, shared by
  /// [_searchBooklists] and [booklistsPageUrl] so the two
  /// constructions cannot drift apart.
  static Map<String, dynamic> _booklistListParams({
    required String query,
    String? order,
    required int page,
  }) {
    final params = <String, dynamic>{
      'searchQuery': query,
      'page': page,
    };
    if (order != null) params['order'] = order;
    return params;
  }

  Future<ApiResponse<BooklistsPage>> _searchBooklists(
    String path, {
    required String query,
    String? order,
    required int page,
  }) async {
    final params = _booklistListParams(
      query: query,
      order: order,
      page: page,
    );
    // Call [_get] directly so a failure can report its real cause:
    // the old code collapsed every failure into a bare
    // "booklists failed", which hid whether the page 302'd, hit a wall,
    // timed out, or came back as JSON. The `Accept: text/html` override
    // is needed because the shared Dio default is `application/json`,
    // and the site answers a page route asked for as JSON with JSON
    // (or an error) instead of the page.
    final raw = await _get(
      path,
      query: params,
      extraHeaders: const {'Accept': 'text/html'},
    );
    final status = raw.status;
    if (status == null || status < 200 || status >= 300) {
      return ApiResponse.fail(
        raw.error ?? 'booklists failed (HTTP $status)',
        statusCode: status,
      );
    }
    final html = raw.body;
    if (html == null || html.isEmpty) {
      return ApiResponse.fail(
        raw.error ?? 'booklists failed',
        statusCode: status,
      );
    }
    // A 200 answer can still be the wall (challenge page with a 200
    // status): it parses to an empty list, which would look like "no
    // booklists". Fail loudly instead so the caller can fall back to
    // the WebView solver like it does for the 503 case.
    if (_looksLikeChallengePage(html)) {
      return ApiResponse.fail(
        'HTTP $status: browser check page',
        statusCode: status,
      );
    }
    onBooklistHtmlLoaded?.call(
      booklistsPageUrl(
        mine: path == '/booklists/my',
        query: query,
        order: order,
        page: page,
      ),
      html,
    );
    return ApiResponse.ok(parseBooklistsPage(html, baseUrl: _base));
  }

  /// Absolute URL of a user's profile page, for callers that fetch the
  /// HTML themselves (e.g. through the WebView challenge solver when
  /// the mirror walls Dio). Same path construction as
  /// [getUserProfileBooklists] — the app must not rebuild it.
  String userProfilePageUrl({
    required String userId,
    required String userHash,
  }) {
    return '$_base/profile/$userId/$userHash';
  }

  /// Booklists on one user's profile page, from the profile document
  /// (`GET /profile/{userId}/{hash}` — one HTML document carrying
  /// every tab, with the booklists tab server-rendered as
  /// `<z-booklist>` elements; see [parseUserProfileBooklists]).
  /// [userHash] is the profile hash from a comment's `user.hash`
  /// (NOT the avatar filename suffix). Empty list when the user has
  /// no booklists. The profile page is an HTML route, so like the
  /// list pages it can answer with the browser-check wall — reported
  /// as `HTTP 503: browser check page` so the caller can fall back
  /// to the WebView solver.
  Future<ApiResponse<List<Booklist>>> getUserProfileBooklists({
    required String userId,
    required String userHash,
  }) async {
    if (userId.isEmpty) {
      return ApiResponse.fail('missing user id');
    }
    if (userHash.isEmpty) {
      return ApiResponse.fail('missing profile hash');
    }
    final raw = await _get(
      '/profile/$userId/$userHash',
      extraHeaders: const {'Accept': 'text/html'},
    );
    final status = raw.status;
    if (status == null || status < 200 || status >= 300) {
      return ApiResponse.fail(
        raw.error ?? 'profile booklists failed (HTTP $status)',
        statusCode: status,
      );
    }
    final html = raw.body;
    if (html == null || html.isEmpty) {
      return ApiResponse.fail(
        raw.error ?? 'profile booklists failed',
        statusCode: status,
      );
    }
    if (_looksLikeChallengePage(html)) {
      return ApiResponse.fail(
        'HTTP $status: browser check page',
        statusCode: status,
      );
    }
    onBooklistHtmlLoaded?.call(
      userProfilePageUrl(userId: userId, userHash: userHash),
      html,
    );
    return ApiResponse.ok(parseUserProfileBooklists(html, baseUrl: _base));
  }

  /// Books on the FIRST page of one booklist, parsed from the detail
  /// page's own HTML (`/booklist/{id}/{hash}/{slug}.html`, via
  /// [parseBooklistDetailBooks]).
  ///
  /// Page 1 is never served by the JSON endpoint (see
  /// [getBooklistBooks]) — it is server-rendered into the detail
  /// document as `<z-bookcard>` elements. The detail page is an HTML
  /// route, so like the list pages it can answer with the browser-check
  /// wall: a challenge page is reported as `HTTP 503: browser check
  /// page` (via [_looksLikeChallengePage]) so the caller can fall back
  /// to the WebView solver, exactly like the booklists screen does.
  /// The request stays on the current mirror (only the path of
  /// [Booklist.url] is used) and carries the session Cookie.
  Future<ApiResponse<List<Book>>> getBooklistDetailBooks(
    Booklist list,
  ) async {
    final path = Uri.tryParse(list.url)?.path ?? '';
    if (path.isEmpty) {
      return ApiResponse.fail('booklist has no page url');
    }
    // Call [_get] directly so a failure can report
    // its real cause, like [_searchBooklists] does.
    final raw = await _get(
      path,
      extraHeaders: const {'Accept': 'text/html'},
    );
    final status = raw.status;
    if (status == null || status < 200 || status >= 300) {
      return ApiResponse.fail(
        raw.error ?? 'booklist failed (HTTP $status)',
        statusCode: status,
      );
    }
    final html = raw.body;
    if (html == null || html.isEmpty) {
      return ApiResponse.fail(
        raw.error ?? 'booklist failed',
        statusCode: status,
      );
    }
    if (_looksLikeChallengePage(html)) {
      return ApiResponse.fail(
        'HTTP $status: browser check page',
        statusCode: status,
      );
    }
    onBooklistHtmlLoaded?.call(list.url, html);
    return ApiResponse.ok(parseBooklistDetailBooks(html, baseUrl: _base));
  }

  /// Books on page 2 and up of one booklist. The site's own JSON API:
  /// `GET /papi/booklist/{id}/get-books/{page}` answers
  /// `{books: [{book: {...}}], pagination: {total_pages}}`; each inner
  /// `book` maps through [Book.fromJson] (its `href` supplies the
  /// `hash`, which the JSON itself does not carry). The `{id}` is the
  /// NUMERIC list id — the site's own `loadMoreBooks`
  /// (z-booklists-browser.js, captured 2026-11-07) calls exactly this
  /// URL. Pages start at 2: the site's counter starts at 1 and is
  /// incremented before the fetch, so page 1 is never requested — it
  /// is server-rendered into the detail document (see
  /// [getBooklistDetailBooks]), and asking the endpoint for page 1
  /// answers "Requested page not found" (verified on device
  /// 2026-11-07 for both the numeric id and the href hash — the
  /// hash-key theory was wrong). Pass the list's numeric [Booklist.id].
  Future<ApiResponse<BooklistBooksPage>> getBooklistBooks(
    String id, {
    int page = 2,
  }) async {
    final raw = await _get('/papi/booklist/$id/get-books/$page');
    if (raw.json == null) {
      return ApiResponse.fail(raw.error ?? 'booklist failed',
          statusCode: raw.status);
    }
    final json = raw.json!;
    if (!_isSuccess(json)) {
      return ApiResponse.fail(
        (json['error'] ?? json['message'])?.toString() ?? 'booklist failed',
        statusCode: raw.status,
      );
    }
    final list = json['books'];
    if (list is! List) {
      return ApiResponse.fail('booklist response had no books',
          statusCode: raw.status);
    }
    final books = list
        .whereType<Map<String, dynamic>>()
        .map((e) => e['book'])
        .whereType<Map<String, dynamic>>()
        .map(Book.fromJson)
        .toList();
    final pagination = json['pagination'];
    var totalPages = 1;
    if (pagination is Map<String, dynamic>) {
      final rawTotal = pagination['total_pages'];
      totalPages = rawTotal is int
          ? rawTotal
          : int.tryParse(rawTotal.toString()) ?? 1;
    }
    return ApiResponse.ok(
      BooklistBooksPage(books: books, totalPages: totalPages),
    );
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

  /// Create a booklist owned by the signed-in user. `POST
  /// /papi/booklist/create` with a JSON body `{title, description}`
  /// sent as `text/plain` (the same transport as [postBookComment],
  /// so redirects are followed). Request shape taken from a browser
  /// capture on 2026-11-07 (Firefox, zh.z-library.sk), which showed no
  /// response data: the site answers with an empty body, so a 2xx
  /// with an empty body is success.
  ///
  /// A JSON answer is still handled leniently in case the site starts
  /// returning one: an explicit failure flag or an `error`/`message`
  /// field fails the call, otherwise it counts as created.
  /// [ApiResponse.data] is the new list only when a JSON response
  /// carries one in a recognizable shape, and null otherwise (always
  /// null today) — callers must not depend on it and should reload the
  /// "my booklists" page after a successful create.
  Future<ApiResponse<Booklist?>> createBooklist({
    required String title,
    String description = '',
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      return ApiResponse.fail('booklist title is empty');
    }
    final raw = await _postText(
      '/papi/booklist/create',
      jsonEncode({'title': cleanTitle, 'description': description.trim()}),
    );
    final status = raw.status;
    final json = raw.json;
    if (json == null) {
      // The create call answers with an EMPTY body (confirmed by the
      // 2026-11-07 capture: no response data), so a 2xx with no body
      // is the success case. [_fromResponse] marks it with an
      // 'empty response' error and leaves [_Raw.body] null. Anything
      // else without JSON (a non-JSON page, a wall, a transport error,
      // a non-2xx status) is a failure and keeps its real cause.
      final is2xx = status != null && status >= 200 && status < 300;
      final emptyBody = raw.body == null &&
          (raw.error?.startsWith('empty response') ?? false);
      if (is2xx && emptyBody) {
        return ApiResponse.ok(null);
      }
      return ApiResponse.fail(
        raw.error ?? 'create booklist failed',
        statusCode: status,
      );
    }
    if (!_isSuccess(json)) {
      return ApiResponse.fail(
        _plainError(
          (json['error'] ?? json['message'])?.toString(),
          'create booklist failed',
        ),
        statusCode: status,
      );
    }
    return ApiResponse.ok(_booklistFromCreateResponse(json, cleanTitle));
  }

  /// Add a book to one of the signed-in user's booklists:
  /// `GET /papi/booklist/{booklistId}/add-book/{bookId}`, confirmed
  /// by a packet capture on 2026-11-09 (Firefox, zh.z-library.sk):
  /// HTTP 200 with `{"success": 1, "book": {"readlist_id": 4090055, "book_id": "18337950", "date": "2026-11-09T08:04:24.000000Z"}}`.
  /// No request body (GET). The site's submenu shows a filled bookmark
  /// when the book is already in a list, so this endpoint is likely
  /// a toggle (clicking again removes the book) — removing a book
  /// from a list is NOT implemented; its response shape is unknown.
  Future<ApiResponse<bool>> addBookToBooklist({
    required int booklistId,
    required int bookId,
  }) async {
    final raw = await _getWithRedirects(
      '/papi/booklist/$booklistId/add-book/$bookId',
    );
    if (raw.json == null) {
      return ApiResponse.fail(
        raw.error ?? 'add to booklist failed',
        statusCode: raw.status,
      );
    }
    final json = raw.json!;
    if (!_isSuccess(json)) {
      return ApiResponse.fail(
        _plainError(
          (json['error'] ?? json['message'])?.toString(),
          'add to booklist failed',
        ),
        statusCode: raw.status,
      );
    }
    return ApiResponse.ok(true);
  }

  /// Remove a book from one of the signed-in user's booklists:
  /// `GET /papi/booklist/{booklistId}/remove-book/{bookId}`, confirmed
  /// by a packet capture on 2026-11-09 (Firefox, zh.z-library.sk):
  /// list 4096101, book 161286730, HTTP 200 with `{"success": 1}`.
  /// No request body (GET). This is a separate endpoint, NOT a toggle
  /// of [addBookToBooklist] — the site calls it when the filled
  /// bookmark in a list's submenu is clicked again.
  Future<ApiResponse<bool>> removeBookFromBooklist({
    required int booklistId,
    required int bookId,
  }) async {
    final raw = await _getWithRedirects(
      '/papi/booklist/$booklistId/remove-book/$bookId',
    );
    final status = raw.status;
    final json = raw.json;
    if (json == null) {
      // Same precedent as [deleteBooklist]: a final 2xx with an empty
      // body counts as removed; anything else without JSON (a wall, a
      // transport error, a non-2xx status) is a failure.
      final is2xx = status != null && status >= 200 && status < 300;
      final emptyBody = raw.body == null &&
          (raw.error?.startsWith('empty response') ?? false);
      if (is2xx && emptyBody) {
        return ApiResponse.ok(true);
      }
      return ApiResponse.fail(
        raw.error ?? 'remove from booklist failed',
        statusCode: status,
      );
    }
    if (!_isSuccess(json)) {
      return ApiResponse.fail(
        _plainError(
          (json['error'] ?? json['message'])?.toString(),
          'remove from booklist failed',
        ),
        statusCode: status,
      );
    }
    return ApiResponse.ok(true);
  }

  /// Delete one of the signed-in user's booklists:
  /// `GET /papi/booklist/{booklistId}/delete`, confirmed by a packet
  /// capture on 2026-11-09 (Firefox, zh.z-library.sk). The first
  /// response is 307 to the same URL with a `__diamwall` set-cookie
  /// (the DDoS-Guard challenge, not delete logic); the list was gone
  /// from the profile BOOKLISTS tab afterwards, so the delete itself
  /// succeeded. The final response body after following the redirect
  /// was never observed, so a non-JSON 2xx final response counts as
  /// success only when it is an empty body (same precedent as
  /// [createBooklist]) — an HTML final page fails instead.
  Future<ApiResponse<bool>> deleteBooklist(int booklistId) async {
    final raw = await _getWithRedirects('/papi/booklist/$booklistId/delete');
    final status = raw.status;
    final json = raw.json;
    if (json == null) {
      final is2xx = status != null && status >= 200 && status < 300;
      final emptyBody = raw.body == null &&
          (raw.error?.startsWith('empty response') ?? false);
      if (is2xx && emptyBody) {
        return ApiResponse.ok(true);
      }
      return ApiResponse.fail(
        raw.error ?? 'delete booklist failed',
        statusCode: status,
      );
    }
    if (!_isSuccess(json)) {
      return ApiResponse.fail(
        _plainError(
          (json['error'] ?? json['message'])?.toString(),
          'delete booklist failed',
        ),
        statusCode: status,
      );
    }
    return ApiResponse.ok(true);
  }

  /// Best-effort read of the list a create call returned. The response
  /// shape is unconfirmed, so this tries the plausible wrappers
  /// (`booklist`, `list`, `data`, or the top level) and needs a numeric
  /// `id` to count as a list. Returns null when nothing matches.
  Booklist? _booklistFromCreateResponse(
    Map<String, dynamic> json,
    String title,
  ) {
    for (final candidate in [
      json['booklist'],
      json['list'],
      json['data'],
      json,
    ]) {
      if (candidate is! Map<String, dynamic>) continue;
      final id = candidate['id']?.toString() ?? '';
      if (!RegExp(r'^\d+$').hasMatch(id)) continue;
      final name = candidate['title']?.toString() ??
          candidate['topic']?.toString() ??
          title;
      return Booklist(
        id: id,
        name: name,
        description: candidate['description']?.toString() ?? '',
        count: 0,
        url: '$_base/booklist/$id',
      );
    }
    return null;
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
  }) async {
    final file = File(savePath);
    final start = await file.exists() ? await file.length() : 0;
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
      await file.writeAsBytes(const []);
      return _downloadOnce(
        link,
        savePath,
        headers,
        onProgress: onProgress,
        cancelToken: cancelToken,
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
      throw StateError(
        'download answered an HTML page '
        '(HTTP $code, content-type $contentType) — the mirror is likely '
        'serving a challenge or error page instead of the file',
      );
    }

    final sink = file.openWrite(mode: resumed ? FileMode.append : FileMode.write);
    var received = resumed ? start : 0;
    try {
      await for (final chunk in res.data!.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } finally {
      await sink.close();
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
          _isInvalidHashError(e.message.toString())) {
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
