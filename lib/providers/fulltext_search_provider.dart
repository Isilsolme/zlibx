import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

import '../services/fulltext_repository.dart';
import 'auth_provider.dart';
import 'zlibrary_provider.dart';

// ── Full-text search ────────────────────────────────────────────────

/// Parameters for one full-text search. `yearFrom` / `yearTo` are
/// supported by the plugin but not exposed in the filter UI (v1) —
/// the sheet has no year controls, same as the general search.
class FullTextSearchParams {
  final String query;

  /// `words` （按字搜索， default) or `phrase` （按词搜索）.
  final String type;

  /// `e=1` （精确对应）.
  final bool exact;
  final int? yearFrom;
  final int? yearTo;
  final List<String>? languages;
  final List<String>? extensions;

  /// One of popular / bestmatch / date / titleA / title / year /
  /// filesize / filesizeA. Never sent to the eapi search.
  final String? order;

  const FullTextSearchParams({
    required this.query,
    this.type = 'words',
    this.exact = false,
    this.yearFrom,
    this.yearTo,
    this.languages,
    this.extensions,
    this.order,
  });
}

class FullTextSearchState {
  final List<FullTextHit> hits;

  /// The total from the results tab (`全文检索 (N)`).
  final int total;
  final int currentPage;
  final int totalPages;

  /// True when the next page may exist. Set from the short-page
  /// rule (a page with fewer than 50 hits is the last one) — the
  /// same rule the category pages use. `totalPages` is display-only:
  /// `pagerOptions` is absent on some pages, where it defaults to 1
  /// and must not cut pagination short.
  final bool hasMore;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasSearched;

  /// Raw error string, or null. The screen maps the known
  /// [fulltextTokenUnavailable] value to its localized message.
  final String? error;

  /// True when the search was refused because nobody is signed in
  /// (the token cannot be fetched without a session). The screen
  /// renders the login prompt instead of the error text.
  final bool loginRequired;

  const FullTextSearchState({
    this.hits = const [],
    this.total = 0,
    this.currentPage = 1,
    this.totalPages = 1,
    this.hasMore = true,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasSearched = false,
    this.error,
    this.loginRequired = false,
  });

  FullTextSearchState copyWith({
    List<FullTextHit>? hits,
    int? total,
    int? currentPage,
    int? totalPages,
    bool? hasMore,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasSearched,
    String? error,
    bool clearError = false,
    bool? loginRequired,
  }) {
    return FullTextSearchState(
      hits: hits ?? this.hits,
      total: total ?? this.total,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      hasMore: hasMore ?? this.hasMore,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasSearched: hasSearched ?? this.hasSearched,
      error: clearError ? null : (error ?? this.error),
      loginRequired: loginRequired ?? this.loginRequired,
    );
  }
}

class FullTextSearchNotifier extends Notifier<FullTextSearchState> {
  // Getter, not a `late final` field: ref.invalidate re-runs build()
  // on the SAME notifier instance and a second late-final assignment
  // throws LateInitializationError (same documented pitfall as
  // SearchNotifier above).
  FulltextRepository get _repository =>
      FulltextRepository(ref.read(zlibraryApiProvider));

  FullTextSearchParams? _lastParams;
  int _requestId = 0;

  @override
  FullTextSearchState build() {
    return const FullTextSearchState();
  }

  /// The site renders 50 hits per full-text page.
  static int get pageSize => ZLibraryFullText.fulltextPageSize;

  /// TEMPORARY diagnostic: the last full-text search's traffic block
  /// (see `FulltextRepository.lastDiagnostics`). Null before the
  /// first search.
  String? get lastDiagnostics => _repository.lastDiagnostics;

  Future<void> search(FullTextSearchParams params) async {
    final requestId = ++_requestId;
    _lastParams = params;
    // The token lives in the signed-in session: without a login
    // there is nothing to fetch it from. Intercept here instead of
    // letting the plugin fail with the generic unavailable error.
    if (ref.read(authProvider).user == null) {
      state = const FullTextSearchState(
        isLoading: false,
        hasSearched: true,
        loginRequired: true,
      );
      return;
    }
    state = const FullTextSearchState(isLoading: true, hasSearched: true);
    final result = await _loadPage(params, 1);
    if (requestId != _requestId) return;
    final page = result.page;
    if (page == null) {
      state = state.copyWith(
        error: result.error ?? 'fulltext search failed',
        isLoading: false,
      );
      return;
    }
    state = FullTextSearchState(
      hits: page.hits,
      total: page.total,
      currentPage: 1,
      totalPages: page.totalPages,
      hasMore: page.hits.length == pageSize,
      hasSearched: true,
    );
  }

  /// Load-more for page 2 and up. A failed later page must not
  /// silently end the list: a network blip would look like "no more
  /// books" with no way back. Keep the state so the next scroll
  /// event re-enters loadMore and retries.
  Future<void> loadMore() async {
    final s = state;
    final params = _lastParams;
    if (params == null ||
        s.isLoading ||
        s.isLoadingMore ||
        !s.hasMore ||
        s.error != null ||
        s.loginRequired) {
      return;
    }
    final page = s.currentPage + 1;
    final requestId = _requestId;
    state = s.copyWith(isLoadingMore: true);
    final result = await _loadPage(params, page);
    if (requestId != _requestId) return;
    final data = result.page;
    if (data == null) {
      state = state.copyWith(isLoadingMore: false);
      return;
    }
    final seen = {for (final hit in s.hits) hit.book.id};
    final merged = List<FullTextHit>.of(s.hits);
    for (final hit in data.hits) {
      if (seen.add(hit.book.id)) merged.add(hit);
    }
    state = state.copyWith(
      hits: merged,
      total: data.total,
      currentPage: page,
      totalPages: data.totalPages,
      hasMore: data.hits.length == pageSize,
      isLoadingMore: false,
    );
  }

  void reset() {
    _lastParams = null;
    state = const FullTextSearchState();
  }

  /// Loads one page: Dio first, the WebView solver on the
  /// browser-check wall. Returns the page, or null page + an error
  /// message when both paths failed.
  Future<({FullTextSearchPage? page, String? error})> _loadPage(
    FullTextSearchParams params,
    int page,
  ) async {
    try {
      final response = await _repository.search(
        query: params.query,
        type: params.type,
        exact: params.exact,
        yearFrom: params.yearFrom,
        yearTo: params.yearTo,
        languages: params.languages,
        extensions: params.extensions,
        order: params.order,
        page: page,
      );
      final data = response.data;
      if (response.success && data != null) {
        return (page: data, error: null);
      }
      final error = response.error ?? 'fulltext search failed';
      if (_repository.isChallengeError(response.error)) {
        return _loadPageViaSolver(
          params,
          page,
          originalError: error,
        );
      }
      return (page: null, error: error);
    } catch (e) {
      return (page: null, error: e.toString());
    }
  }

  Future<({FullTextSearchPage? page, String? error})> _loadPageViaSolver(
    FullTextSearchParams params,
    int page, {
    required String originalError,
  }) async {
    final user = ref.read(authProvider).user;
    final url = _repository.searchPageUrl(
      query: params.query,
      type: params.type,
      exact: params.exact,
      yearFrom: params.yearFrom,
      yearTo: params.yearTo,
      languages: params.languages,
      extensions: params.extensions,
      order: params.order,
      page: page,
    );
    final html = await _repository.fetchViaSolver(
      url,
      userId: user?.id,
      userKey: user?.remixUserkey,
    );
    if (html == null) return (page: null, error: originalError);
    final parsed = _repository.parsePage(
      html,
      baseUrl: Uri.parse(url).origin,
      expectedQuery: params.query,
      solverUrl: url,
    );
    if (parsed == null) return (page: null, error: originalError);
    return (page: parsed, error: null);
  }
}

final fulltextSearchProvider =
    NotifierProvider<FullTextSearchNotifier, FullTextSearchState>(
      FullTextSearchNotifier.new,
    );
