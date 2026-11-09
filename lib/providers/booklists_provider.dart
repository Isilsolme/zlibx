import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

import '../services/booklist_html_cache.dart';
import '../services/booklist_solver.dart';
import '../services/external_logger.dart';
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

  final AppLogger _logger = AppLogger();

  bool _alive = true;

  /// Bumped by every fresh load (tab switch, search, retry, refresh);
  /// every in-flight load carries the generation it started with, and a
  /// slower response for an old tab/query is dropped.
  int _generation = 0;

  /// Identity of the loadMore currently holding the [BooklistsState.isLoadingMore]
  /// flag (0 = none). A stale loadMore's `finally` must not clear a
  /// newer loadMore's flag — only the holder may release it.
  int _loadMoreToken = 0;
  int _loadMoreOwner = 0;

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

  /// Delete one of the user's own lists (mine tab only): optimistic
  /// removal, restored on failure. Returns the API response so the
  /// caller can show the failure message; the guard cases return a
  /// failure response and change nothing.
  ///
  /// The restore is guarded by the generation captured at delete
  /// start: a refresh that ran during the delete owns the
  /// authoritative list, so a stale restore must not re-insert a
  /// list the refresh already dropped (or duplicate one it kept).
  Future<ApiResponse<bool>> deleteBooklist(Booklist list) async {
    if (state.tab != BooklistTab.mine ||
        state.phase != BooklistsPhase.ready) {
      return ApiResponse.fail('delete booklist not available');
    }
    final index = state.lists.indexWhere((l) => l.id == list.id);
    if (index < 0) return ApiResponse.fail('delete booklist not available');
    final listId = int.tryParse(list.id);
    if (listId == null) {
      return ApiResponse.fail('delete booklist not available');
    }
    final generation = _generation;
    final removed = state.lists[index];
    state = state.copyWith(
      lists: [...state.lists]..removeAt(index),
    );
    try {
      final response =
          await ref.read(zlibraryApiProvider).deleteBooklist(listId);
      if (!_alive) return response;
      if (response.success) return response;
      _restoreDeleted(generation, removed, index);
      return response;
    } catch (_) {
      if (!_alive) return ApiResponse.fail('delete booklist failed');
      _restoreDeleted(generation, removed, index);
      return ApiResponse.fail('delete booklist failed');
    }
  }

  /// Re-inserts a list whose delete failed — only when the list has
  /// not been replaced since the delete started (a refresh owns the
  /// authoritative list then) and the list is not already present.
  void _restoreDeleted(int generation, Booklist removed, int index) {
    if (!_isCurrent(generation)) return;
    if (state.lists.any((item) => item.id == removed.id)) return;
    state = state.copyWith(
      lists: [...state.lists]
        ..insert(index.clamp(0, state.lists.length), removed),
    );
  }

  /// A book was added to one of the user's lists (from the
  /// add-to-booklist picker): bump that list's count optimistically
  /// so the booklists screen shows the new count without waiting
  /// for its next background refresh. No-op when the list is not
  /// in the currently loaded page.
  void noteBookAdded(String listId) {
    final index = state.lists.indexWhere((item) => item.id == listId);
    if (index < 0) return;
    final list = state.lists[index];
    final count = list.count;
    if (count == null) return;
    final updated = Booklist(
      id: list.id,
      name: list.name,
      description: list.description,
      author: list.author,
      count: count + 1,
      views: list.views,
      coverUrl: list.coverUrl,
      url: list.url,
      previewBooks: list.previewBooks,
    );
    final lists = [...state.lists]..[index] = updated;
    state = state.copyWith(lists: lists);
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
    // Only the own-lists tab needs a login; the discover tab is
    // public, so a signed-out user must still be able to browse it.
    if (state.tab == BooklistTab.mine &&
        ref.read(authProvider).user == null) {
      state = state.copyWith(
        phase: BooklistsPhase.loggedOut,
        lists: const [],
      );
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
    BooklistsPage? cachedPage;
    if (cachedHtml != null && !BooklistSolver.isChallengeHtml(cachedHtml)) {
      // The cached HTML is user-unreachable data from an older app run;
      // a parse failure there must not leave the screen loading forever.
      // Treat a broken cache like a cache miss and fall through to the
      // network path.
      try {
        cachedPage = parseBooklistsPage(
          cachedHtml,
          baseUrl: Uri.parse(url).origin,
        );
      } catch (e) {
        _logger.warning('Cached booklists page failed to parse, ignoring it',
            tag: 'Booklists', error: e);
        cachedPage = null;
      }
    }
    if (cachedPage != null) {
      // Stale-while-revalidate: paint the last-known lists instantly,
      // then refresh page 1 in the background.
      _applyPage(cachedPage, 1, replace: true);
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
    final tracksLoadMore = page > 1;
    // This loadMore's identity: only the request currently holding
    // the flag may release it (see the finally below).
    final loadMoreToken = tracksLoadMore ? ++_loadMoreToken : 0;
    if (tracksLoadMore) {
      _loadMoreOwner = loadMoreToken;
      state = state.copyWith(isLoadingMore: true);
    }
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
    } finally {
      // A stale response (a refresh bumped the generation while this
      // loadMore was in flight) is dropped above WITHOUT any path that
      // resets isLoadingMore — the flag then blocks every future
      // loadMore() at the `s.isLoadingMore` guard forever. Reset it
      // here so pagination can never dead-lock. But only the request
      // currently holding the flag may release it: a newer loadMore
      // may have started since (a refresh cleared the way), and
      // clearing its flag would let a duplicate loadMore through.
      if (tracksLoadMore && _loadMoreOwner == loadMoreToken) {
        _loadMoreOwner = 0;
        state = state.copyWith(isLoadingMore: false);
      }
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
    // It still must clear a leftover loadMore flag — a loadMore that ran
    // concurrently with this refresh had its response dropped.
    if (replace) {
      state = state.copyWith(isLoadingMore: false);
      return;
    }
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

/// A second, independent [BooklistsController] for the add-to-booklist
/// picker. The picker only ever shows the user's own lists, but it
/// must not switch the shared [booklistsControllerProvider]'s tab to
/// mine as a side effect (the booklists screen may be sitting on the
/// discover tab). This instance defaults to the mine tab and loads
/// its own page 1; it is disposed with the dialog.
final addToBooklistPickerProvider =
    NotifierProvider.autoDispose<BooklistsController, BooklistsState>(
      BooklistsController.new,
    );
