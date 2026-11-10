// Downloads domain of [ZLibraryApi]: resolving the file link and
// streaming the file to disk or into a pending MediaStore entry.
// Split out of `zlibrary_api.dart` (item 7, step 4, final) as a mixin
// in the same library, `on ZLibraryApiBase`, so it can use the base
// class's private HTTP helpers (`_dio`, `_headers`, `_base`,
// `_fromError`) and session fields directly. The hash-resolution
// helper (`resolveEapiHash`) lives in the base class because both
// this mixin (`_resolveDownloadLink`) and the search mixin
// (`getBookInfo`) call it. A mixin in a separate library could not
// see those privates without changing the public interface (which
// the six test fakes implement).
part of 'zlibrary_api.dart';

/// Download methods for [ZLibraryApi].
mixin ZLibraryDownloads on ZLibraryApiBase {
  // ── Download ───────────────────────────────────────────────────────

  /// Resolve the file link via `/eapi/book/{id}/{hash}/file` and stream
  /// the file to [savePath]. Throws on failure (the app catches it and
  /// re-checks the download quota via getProfile).
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
  /// [resolveEapiHash] (see getBookInfo).
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
      // Same short-hash trap as getBookInfo: the file endpoint
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
