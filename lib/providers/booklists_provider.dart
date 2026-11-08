import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

import '../services/booklist_html_cache.dart';
import '../services/booklist_solver.dart';
import 'auth_provider.dart';
import 'zlibrary_provider.dart';

enum BooklistTab { mine, discover }

/// What the booklists screen should show.
enum BooklistsPhase { loading, loggedOut, error, ready }

class BooklistsState {
  final BooklistTab tab;
  final String query;
  final BooklistsPhase phase;
  final List<Booklist> lists;
  final int nextPage;
  final bool hasMore;
  final bool isLoadingMore;
  final String? error;

  const BooklistsState({
    this.tab = BooklistTab.mine,
    this.query = '',
    this.phase = BooklistsPhase.loading,
    this.lists = const [],
    this.nextPage = 1,
    this.hasMore = true,
    this.isLoadingMore = false,
    this.error,
  });

  BooklistsState copyWith({
    BooklistTab? tab,
    String? query,
    BooklistsPhase? phase,
    List<Booklist>? lists,
    int? nextPage,
    bool? hasMore,
    bool? isLoadingMore,
    String? error,
    bool clearError = false,
  }) {
    return BooklistsState(
      tab: tab ?? this.tab,
      query: query ?? this.query,
      phase: phase ?? this.phase,
      lists: lists ?? this.lists,
      nextPage: nextPage ?? this.nextPage,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Own booklists + public booklists to discover, with search and paging.
///
/// List pages are the site's HTML (`/booklists`, `/booklists/my`). A
/// cached page paints instantly and is revalidated in the background
/// (a failed background refresh keeps the cached lists); when Dio hits
/// the browser-check wall the same page is fetched via the WebView
/// solver ([BooklistSolver]).
class BooklistsController extends AutoDisposeNotifier<BooklistsState> {
  static const int _pageSize = 10;

  bool _alive = true;

  /// Bumped by every fresh load (tab switch, search, retry, refresh);
  /// every in-flight load carries the generation it started with, and a
  /// slower response for an old tab/query is dropped.
  int _generation = 0;

  @override
  BooklistsState build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    Future<void>.microtask(loadFirst);
    return const BooklistsState();
  }

  bool _isCurrent(int generation) => _alive && generation == _generation;

  /// Cache partition: the own-lists tab is account-scoped (the same URL
  /// serves another account's lists after a switch); discover is public.
  String? _accountIdFor(BooklistTab tab) => tab == BooklistTab.mine
      ? (ref.read(authProvider).user?.id ?? 'signed-out')
      : null;

  void setTab(BooklistTab tab) {
    if (tab == state.tab) return;
    state = state.copyWith(tab: tab);
    unawaited(loadFirst());
  }

  void search(String query) {
    final trimmed = query.trim();
    if (trimmed == state.query) return;
    state = state.copyWith(query: trimmed);
    unawaited(loadFirst());
  }

  /// Pull-to-refresh: revalidate page 1 in place when lists are on
  /// screen, otherwise do a full first load.
  Future<void> refresh() async {
    if (state.phase != BooklistsPhase.ready || state.lists.isEmpty) {
      return loadFirst();
    }
    if (!_alive) return;
    final generation = ++_generation;
    await _loadPage(
      1,
      replace: true,
      generation: generation,
      accountId: _accountIdFor(state.tab),
    );
  }

  Future<void> loadFirst() async {
    if (!_alive) return;
    if (ref.read(authProvider).user == null) {
      state = state.copyWith(phase: BooklistsPhase.loggedOut);
      return;
    }
    final generation = ++_generation;
    final tab = state.tab;
    final accountId = _accountIdFor(tab);
    final api = ref.read(zlibraryApiProvider);
    final url = api.booklistsPageUrl(
      mine: tab == BooklistTab.mine,
      query: state.query,
      order: tab == BooklistTab.mine ? null : 'popular',
      page: 1,
    );
    final cachedHtml = BooklistHtmlCache.get(url, accountId: accountId);
    if (cachedHtml != null && !BooklistSolver.isChallengeHtml(cachedHtml)) {
      // Stale-while-revalidate: paint the last-known lists instantly,
      // then refresh page 1 in the background.
      _applyPage(
        parseBooklistsPage(cachedHtml, baseUrl: Uri.parse(url).origin),
        1,
        replace: true,
      );
      unawaited(
        _loadPage(1, replace: true, generation: generation, accountId: accountId),
      );
      return;
    }
    state = state.copyWith(
      phase: BooklistsPhase.loading,
      lists: const [],
      nextPage: 1,
      hasMore: true,
      isLoadingMore: false,
      clearError: true,
    );
    await _loadPage(1, generation: generation, accountId: accountId);
  }

  Future<void> loadMore() async {
    final s = state;
    if (!_alive ||
        s.phase != BooklistsPhase.ready ||
        !s.hasMore ||
        s.isLoadingMore) {
      return;
    }
    await _loadPage(
      s.nextPage,
      generation: _generation,
      accountId: _accountIdFor(s.tab),
    );
  }

  Future<void> _loadPage(
    int page, {
    bool replace = false,
    required int generation,
    required String? accountId,
  }) async {
    final api = ref.read(zlibraryApiProvider);
    final tab = state.tab;
    final query = state.query;
    if (page > 1) state = state.copyWith(isLoadingMore: true);
    try {
      final response = tab == BooklistTab.mine
          ? await api.searchMyBooklists(query: query, page: page)
          : await api.searchPublicBooklists(
              query: query,
              order: 'popular',
              page: page,
            );
      if (!_isCurrent(generation)) return;
      final data = response.data;
      if (response.success && data != null) {
        _applyPage(data, page, replace: replace);
        return;
      }
      final error = response.error ?? 'Failed to load booklists';
      if (BooklistSolver.isChallengeError(response.error)) {
        await _loadViaSolver(
          page,
          error,
          replace: replace,
          generation: generation,
          accountId: accountId,
        );
        return;
      }
      _applyFailure(page, error, replace: replace);
    } catch (e) {
      if (!_isCurrent(generation)) return;
      _applyFailure(page, e.toString(), replace: replace);
    }
  }

  /// Fetch one list page through the WebView solver and parse it. The
  /// own-lists page needs the login session. A failure reports the fast
  /// path's original error, so retry re-runs fast-then-solver.
  Future<void> _loadViaSolver(
    int page,
    String originalError, {
    required bool replace,
    required int generation,
    required String? accountId,
  }) async {
    final api = ref.read(zlibraryApiProvider);
    final tab = state.tab;
    final url = api.booklistsPageUrl(
      mine: tab == BooklistTab.mine,
      query: state.query,
      order: tab == BooklistTab.mine ? null : 'popular',
      page: page,
    );
    String? userId;
    String? userKey;
    if (tab == BooklistTab.mine) {
      final user = ref.read(authProvider).user;
      userKey = user?.remixUserkey;
      if (user == null || userKey == null || userKey.isEmpty) {
        // The session key is gone — show the login prompt.
        state = state.copyWith(phase: BooklistsPhase.loggedOut);
        return;
      }
      userId = user.id;
    }
    final html = await BooklistSolver.fetchHtml(
      api,
      url,
      accountId: accountId,
      userId: userId,
      userKey: userKey,
    );
    if (!_isCurrent(generation)) return;
    if (html == null) {
      _applyFailure(page, originalError, replace: replace);
      return;
    }
    _applyPage(
      parseBooklistsPage(html, baseUrl: Uri.parse(url).origin),
      page,
      replace: replace,
    );
  }

  void _applyPage(BooklistsPage data, int page, {bool replace = false}) {
    state = state.copyWith(
      phase: BooklistsPhase.ready,
      // A background refresh replaces the cached page instead of
      // appending to it.
      lists: replace || page == 1 ? data.lists : [...state.lists, ...data.lists],
      // The site pages at 10 lists; a short page ends the list. A parsed
      // page count (0 = unknown) is the second signal.
      hasMore:
          data.lists.length >= _pageSize &&
          (data.totalPages <= 0 || page < data.totalPages),
      nextPage: page + 1,
      isLoadingMore: false,
      clearError: true,
    );
  }

  void _applyFailure(int page, String message, {bool replace = false}) {
    // A background refresh (cached lists on screen) never errors: the
    // cached data stays, and the next open or pull-to-refresh retries.
    if (replace) return;
    if (page == 1) {
      state = state.copyWith(
        phase: BooklistsPhase.error,
        error: message,
        isLoadingMore: false,
      );
    } else {
      state = state.copyWith(isLoadingMore: false, hasMore: false);
    }
  }
}

final booklistsControllerProvider =
    NotifierProvider.autoDispose<BooklistsController, BooklistsState>(
      BooklistsController.new,
    );
