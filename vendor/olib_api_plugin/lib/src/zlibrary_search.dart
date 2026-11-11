// Search & lists domain of [ZLibraryApi]: book search, detail,
// lists (most popular / recommended / recent / saved / downloaded),
// save/unsave, similar books, and comments. Split out of
// `zlibrary_api.dart` (item 7, step 2) as a mixin in the
// same library, `on ZLibraryApiBase`, so it can use the base
// class's private HTTP helpers (`_get`, `_postForm`, `_postText`,
// `_delete`) and session fields directly. The parsing helpers
// (`_booksOf`, `_metaOf`) moved to the base class in step 4,
// because `search` moved there too (both this mixin and the
// downloads mixin call it through the base); `_delete` stays here
// because only this domain uses it. The shared helpers
// (`_postText`, `_isInvalidHashError`) live in the base class
// because other domains use them too. A mixin in a separate
// library could not see those privates without changing the
// public interface (which the six test fakes implement).
part of 'zlibrary_api.dart';

/// Search, detail, lists, and comments methods for [ZLibraryApi].
mixin ZLibrarySearch on ZLibraryApiBase {
  // ── Search & lists ─────────────────────────────────────────────────

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
        ZLibraryApiBase._isInvalidHashError(response.error)) {
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
    if (!ZLibraryApiBase._isSuccess(json)) {
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
    if (!ZLibraryApiBase._isSuccess(raw.json!)) {
      return search(order: 'popular', limit: 20);
    }
    final books = ZLibraryApiBase._booksOf(raw.json!);
    if (books.isEmpty) {
      return search(order: 'popular', limit: 20);
    }
    return ApiResponse.ok(books, meta: ZLibraryApiBase._metaOf(raw.json!));
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
    if (!ZLibraryApiBase._isSuccess(raw.json!)) return getMostPopular();
    final books = ZLibraryApiBase._booksOf(raw.json!);
    if (books.isEmpty) return getMostPopular();
    return ApiResponse.ok(books, meta: ZLibraryApiBase._metaOf(raw.json!));
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
    if (!ZLibraryApiBase._isSuccess(raw.json!)) {
      return ApiResponse.fail(
        (raw.json!['error'] ?? raw.json!['message'])?.toString() ??
            'recently failed',
        statusCode: raw.status,
      );
    }
    return ApiResponse.ok(ZLibraryApiBase._booksOf(raw.json!), meta: ZLibraryApiBase._metaOf(raw.json!));
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
    if (!ZLibraryApiBase._isSuccess(raw.json!)) {
      return ApiResponse.fail(
        (raw.json!['error'] ?? raw.json!['message'])?.toString() ??
            'saved books failed',
        statusCode: raw.status,
      );
    }
    return ApiResponse.ok(ZLibraryApiBase._booksOf(raw.json!), meta: ZLibraryApiBase._metaOf(raw.json!));
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
    if (!ZLibraryApiBase._isSuccess(raw.json!)) {
      return ApiResponse.fail(
        (raw.json!['error'] ?? raw.json!['message'])?.toString() ??
            'downloaded books failed',
        statusCode: raw.status,
      );
    }
    return ApiResponse.ok(ZLibraryApiBase._booksOf(raw.json!), meta: ZLibraryApiBase._metaOf(raw.json!));
  }

  /// Save to "My library". Mirrors the confirmed unsave path.
  Future<ApiResponse<void>> saveBook(String bookId) async {
    final raw = await _get('/eapi/user/book/$bookId/save');
    if (raw.json == null) {
      return ApiResponse.fail(raw.error ?? 'save failed',
          statusCode: raw.status);
    }
    if (!ZLibraryApiBase._isSuccess(raw.json!)) {
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
    if (!ZLibraryApiBase._isSuccess(raw.json!)) {
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
    if (!ZLibraryApiBase._isSuccess(raw.json!)) {
      return ApiResponse.fail(
        (raw.json!['error'] ?? raw.json!['message'])?.toString() ??
            'similar failed',
        statusCode: raw.status,
      );
    }
    return ApiResponse.ok(ZLibraryApiBase._booksOf(raw.json!), meta: ZLibraryApiBase._metaOf(raw.json!));
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
    if (!ZLibraryApiBase._isSuccess(json)) {
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
    if (!ZLibraryApiBase._isSuccess(json)) {
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
    if (!ZLibraryApiBase._isSuccess(json)) {
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
    if (!ZLibraryApiBase._isSuccess(json)) {
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
    if (!ZLibraryApiBase._isSuccess(json)) {
      return ApiResponse.fail(
        (json['error'] ?? json['message'])?.toString() ??
            'delete comment failed',
        statusCode: raw.status,
      );
    }
    return ApiResponse.ok(true);
  }

  /// DELETE with no request body, following redirects by hand — same
  /// pattern as `_postText`: 307/308 are re-sent as DELETE, 301/302/303
  /// are followed as GET (browser behaviour). The session Cookie is
  /// only sent to our own host: a hop to another host drops it. A
  /// same-host hop may re-issue cookies (the DDoS-Guard challenge sets
  /// `__diamwall` on the first 307 and expects the follow-up request to
  /// carry it): they are learned into the session / wall-cookie jar
  /// before following. Cross-host target hops learn nothing.
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
    // Set once the Cookie header has been stripped for a cross-host hop:
    // it stays off for the rest of the chain even if a later hop comes
    // back to our own host (pre-fix behaviour).
    var cookieStripped = false;
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
        // Learn what this hop re-issued before following it. Only a hop
        // that stays on our own host may teach the jar: a cross-host
        // target's cookies must not enter it. The request host only
        // differs from the base after a cross-host target — and cookies
        // set by another host must not enter the jar even when that hop
        // redirects back to us.
        if (next.host == Uri.parse(_base).host &&
            Uri.parse(url).host == Uri.parse(_base).host) {
          _harvestRedirectCookies(
            res.headers['set-cookie'] ?? const <String>[],
          );
        }
        url = next.toString();
        if (next.host != Uri.parse(_base).host) {
          headers = Map<String, String>.from(headers)..remove('Cookie');
          cookieStripped = true;
        } else if (!cookieStripped) {
          // Same-host hop: re-derive the Cookie header from the jar so
          // the follow-up carries what this hop re-issued. Nothing was
          // harvested — the rebuild is a no-op.
          final cookie = _headers['Cookie'];
          if (cookie != null) {
            headers['Cookie'] = cookie;
          } else {
            headers.remove('Cookie');
          }
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

}
