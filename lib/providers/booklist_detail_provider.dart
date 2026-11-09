import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

import '../services/booklist_html_cache.dart';
import '../services/booklist_solver.dart';
import 'auth_provider.dart';
import 'zlibrary_provider.dart';

/// Arguments for BooklistDetailScreen. Equality is by list id and
/// URL so the screen's provider family resolves to the same
/// controller on rebuild, while a list whose page moved (or whose
/// count changed) gets a fresh controller. `canEdit` is deliberately
/// excluded: the screen reads it from its own widget arguments, not
/// from the controller, so it must not force a new controller.
class BooklistDetailArgs {
  final Booklist booklist;

  /// True only when the signed-in user owns this list (opened from the
  /// mine tab of the booklists screen). Only then is removing a book
  /// offered; other users' lists are read-only here.
  final bool canEdit;

  const BooklistDetailArgs({required this.booklist, this.canEdit = false});

  @override
  bool operator ==(Object other) =>
      other is BooklistDetailArgs &&
      other.booklist.id == booklist.id &&
      other.booklist.url == booklist.url;

  @override
  int get hashCode => Object.hash(booklist.id, booklist.url);
}

class BooklistDetailState {
  /// True only while there is no local snapshot to paint yet.
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;
  final List<Book> books;
  final bool hasMore;
  final int nextPage;

  const BooklistDetailState({
    this.isLoading = true,
    this.isLoadingMore = false,
    this.error,
    this.books = const [],
    this.hasMore = true,
    this.nextPage = 2,
  });

  BooklistDetailState copyWith({
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
    bool clearError = false,
    List<Book>? books,
    bool? hasMore,
    int? nextPage,
  }) {
    return BooklistDetailState(
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
      books: books ?? this.books,
      hasMore: hasMore ?? this.hasMore,
      nextPage: nextPage ?? this.nextPage,
    );
  }
}

/// Books inside one booklist. The last-known first page is painted from
/// a parsed Hive cache (or the list page preview as a cold-cache
/// fallback), then the detail page is always revalidated in the
/// background so changes made on the Z-Library website are picked up.
///
/// Page 1 comes from the detail page's own HTML (the site renders the
/// first page into the document; its JSON endpoint only serves page 2
/// and up, numeric id — asking it for page 1 answers "Requested page not
/// found"). Page 2+ comes from `getBooklistBooks`.
class BooklistDetailController
    extends AutoDisposeFamilyNotifier<BooklistDetailState, BooklistDetailArgs> {
  final List<Book> _books = [];
  // O(1) membership checks while pages are appended.
  final Set<int> _bookIds = <int>{};
  // IDs currently represented by the server-rendered first page. On a
  // revalidation, this slice is replaced while page 2+ rows are kept.
  final Set<int> _firstPageIds = <int>{};
  // Books with a remove in flight. The same book cannot be removed
  // twice concurrently; without this, two overlapping removes can
  // each resolve the entry id, then remove/restore the wrong row.
  final Set<int> _removingBookIds = <int>{};

  bool _alive = true;
  int _generation = 0;

  Booklist get _list => arg.booklist;

  String get _accountId => ref.read(authProvider).user?.id ?? 'signed-out';

  @override
  BooklistDetailState build(BooklistDetailArgs arg) {
    _alive = true;
    ref.onDispose(() => _alive = false);
    Future<void>.microtask(loadFirst);
    return const BooklistDetailState();
  }

  bool _isCurrent(int generation) => _alive && generation == _generation;

  Future<void> loadFirst() async {
    if (!_alive) return;
    final generation = ++_generation;
    final list = _list;
    final preview = list.previewBooks;
    final accountId = _accountId;

    // Page 1 is cached independently of the booklist-list preview. The
    // preview belongs to the (possibly stale) list-page response and
    // must never prevent reading a newer detail-page cache.
    final cachedPage = BooklistHtmlCache.getBooksPage(
      list.url,
      1,
      accountId: accountId,
    );
    final cachedHtml = cachedPage == null
        ? BooklistHtmlCache.get(list.url, accountId: accountId)
        : null;
    final usableHtml =
        (cachedHtml != null && !BooklistSolver.isChallengeHtml(cachedHtml))
        ? cachedHtml
        : null;
    List<Book>? htmlBooks;
    if (usableHtml != null) {
      // Same guard as BooklistsController.loadFirst: the cache was written
      // by an older run — a parse failure must not escape loadFirst (which
      // runs from a microtask) and leave the screen loading forever.
      try {
        htmlBooks = parseBooklistDetailBooks(
          usableHtml,
          baseUrl: Uri.parse(list.url).origin,
        );
      } catch (_) {
        htmlBooks = null;
      }
    }
    final initialBooks = cachedPage ?? htmlBooks ?? preview;
    final hasLocalSnapshot =
        cachedPage != null || usableHtml != null || preview.isNotEmpty;

    _books.clear();
    _bookIds.clear();
    _firstPageIds.clear();
    state = BooklistDetailState(isLoading: !hasLocalSnapshot);

    if (hasLocalSnapshot) {
      // Paint cached data immediately (including a cached empty list).
      // Even when the old count says there are no more books, always
      // revalidate: books may have been added on the website since.
      _applyFirstPage(initialBooks);
      state = state.copyWith(isLoadingMore: true);
      await _loadDetailPage(
        background: true,
        generation: generation,
        accountId: accountId,
      );
    } else {
      await _loadDetailPage(generation: generation, accountId: accountId);
    }
    if (!_isCurrent(generation)) return;
    state = state.copyWith(isLoading: false, isLoadingMore: false);
  }

  /// First page: the detail page's own HTML. Dio fast path first; on the
  /// browser-check wall, the WebView solver. In background mode a
  /// failure is silent — the cached/preview books stay on screen.
  Future<void> _loadDetailPage({
    bool background = false,
    required int generation,
    required String accountId,
  }) async {
    final api = ref.read(zlibraryApiProvider);
    final list = _list;
    try {
      final response = await api.getBooklistDetailBooks(list);
      if (!_isCurrent(generation)) return;
      final data = response.data;
      if (response.success && data != null) {
        // Persist the parsed first page so the next visit paints
        // immediately without depending on the list-page preview.
        BooklistHtmlCache.storeBooksPage(
          list.url,
          1,
          data,
          accountId: accountId,
        );
        _applyFirstPage(data);
        return;
      }
      final error = response.error ?? 'Failed to load booklist';
      if (BooklistSolver.isChallengeError(response.error)) {
        await _loadViaSolver(
          error,
          background: background,
          generation: generation,
          accountId: accountId,
        );
        return;
      }
      if (!background) _fail(error);
    } catch (e) {
      if (!_isCurrent(generation)) return;
      if (!background) _fail(e.toString());
    }
  }

  Future<void> _loadViaSolver(
    String originalError, {
    required bool background,
    required int generation,
    required String accountId,
  }) async {
    final api = ref.read(zlibraryApiProvider);
    final url = _list.url;
    // An own list's page needs the session; a public page loads the same
    // either way.
    final user = ref.read(authProvider).user;
    final html = await BooklistSolver.fetchHtml(
      api,
      url,
      accountId: accountId,
      userId: user?.id,
      userKey: user?.remixUserkey,
    );
    if (!_isCurrent(generation)) return;
    if (html == null) {
      if (!background) _fail(originalError);
      return;
    }
    final books = parseBooklistDetailBooks(html, baseUrl: Uri.parse(url).origin);
    BooklistHtmlCache.storeBooksPage(url, 1, books, accountId: accountId);
    _applyFirstPage(books);
  }

  /// Load-more for JSON pages (2 and up). A cached page paints first
  /// (merged by id), then the network revalidates it; a failed refresh
  /// just ends the list with the cached rows still on screen.
  Future<void> loadMore() async {
    final s = state;
    if (!_alive ||
        s.isLoading ||
        s.isLoadingMore ||
        !s.hasMore ||
        s.error != null) {
      return;
    }
    final page = s.nextPage;
    final generation = _generation;
    final api = ref.read(zlibraryApiProvider);
    final list = _list;
    final accountId = _accountId;
    final cachedPage = BooklistHtmlCache.getBooksPage(
      list.url,
      page,
      accountId: accountId,
    );
    if (cachedPage != null) _merge(cachedPage);
    state = state.copyWith(isLoadingMore: true, books: List.of(_books));
    try {
      final response = await api.getBooklistBooks(list.id, page: page);
      if (!_isCurrent(generation)) return;
      final data = response.data;
      if (response.success && data != null) {
        BooklistHtmlCache.storeBooksPage(
          list.url,
          page,
          data.books,
          accountId: accountId,
        );
        // Merge by id: the cached page and the fresh page carry the
        // same books — adding both would duplicate the rows.
        _merge(data.books);
        state = state.copyWith(
          books: List.of(_books),
          hasMore: page < data.totalPages,
          nextPage: page + 1,
          isLoadingMore: false,
        );
      } else {
        // A failed later page must not silently end the list: a network
        // blip would look like "no more books" with no way back (and
        // setting `error` here would trip the loadMore guard above,
        // which blocks retries while an error is set). Keep hasMore so
        // the next scroll event re-enters loadMore and retries.
        state = state.copyWith(isLoadingMore: false);
      }
    } catch (e) {
      if (!_isCurrent(generation)) return;
      // Same as above: keep the list resumable instead of truncating it.
      state = state.copyWith(isLoadingMore: false);
    }
  }

  /// Remove one book from this list: optimistic removal; on failure
  /// the book is restored. On success every cached page of this list
  /// is invalidated so the book does not reappear from a later
  /// page's cache on the next open.
  ///
  /// remove-book takes the readlist ENTRY id (the per-(book, list)
  /// membership-row id from `current-user`), NOT the book id — the
  /// entry id is resolved first and the remove call is only made
  /// with it. A null entry id (book not in this list) or a failed
  /// resolve fails here without calling remove-book at all: falling
  /// back to the book id is the bug that made the server 500 every
  /// app remove.
  ///
  /// Two removes of the same book cannot overlap (a
  /// [_removingBookIds] guard); removes of different books re-locate
  /// their target by id after each await, so a concurrent remove
  /// cannot shift one onto the wrong row. Restore inserts before
  /// the removed book's successor instead of a stale index.
  Future<ApiResponse<bool>> removeBook(Book book) async {
    if (!_alive) return ApiResponse.fail('remove book failed');
    final listId = int.tryParse(_list.id);
    if (listId == null) {
      return ApiResponse.fail('remove book not available');
    }
    if (_books.indexWhere((b) => b.id == book.id) < 0) {
      return ApiResponse.fail('book not in list');
    }
    if (!_removingBookIds.add(book.id)) {
      return ApiResponse.fail('book is already being removed');
    }
    try {
      final entry = await ref.read(zlibraryApiProvider).getReadlistBookId(
        booklistId: listId,
        bookId: book.id,
      );
      if (!_alive) {
        return ApiResponse.fail(entry.error ?? 'remove book failed');
      }
      final entryId = entry.data;
      if (!entry.success || entryId == null) {
        return ApiResponse.fail(
          entry.error ?? 'book is not in this booklist',
        );
      }
      // Re-locate by id: another remove may have shifted the list
      // while the entry id was being resolved.
      final currentIndex = _books.indexWhere((b) => b.id == book.id);
      if (currentIndex < 0) return ApiResponse.fail('book not in list');
      final wasFirstPage = _firstPageIds.contains(book.id);
      final successorId = currentIndex + 1 < _books.length
          ? _books[currentIndex + 1].id
          : null;
      final removed = _books[currentIndex];
      _books.removeAt(currentIndex);
      _bookIds.remove(book.id);
      _firstPageIds.remove(book.id);
      state = state.copyWith(books: List.of(_books));
      final response = await ref
          .read(zlibraryApiProvider)
          .removeBookFromBooklist(
            booklistId: listId,
            readlistBookId: entryId,
          );
      if (response.success) {
        // Invalidate even when the controller is gone — the next
        // open must not paint the deleted book from a page cache.
        BooklistHtmlCache.invalidateBooklist(
          _list.url,
          accountId: _accountId,
        );
      }
      if (!_alive) return response;
      if (response.success) return response;
      // Restore before the successor (or at the end when it is gone):
      // the captured index may be stale after a concurrent remove.
      _bookIds.add(book.id);
      if (wasFirstPage) _firstPageIds.add(book.id);
      final restoreIndex = successorId == null
          ? _books.length
          : _books.indexWhere((b) => b.id == successorId);
      _books.insert(restoreIndex < 0 ? _books.length : restoreIndex, removed);
      state = state.copyWith(books: List.of(_books));
      return response;
    } finally {
      _removingBookIds.remove(book.id);
    }
  }

  void _merge(List<Book> books) {
    for (final book in books) {
      if (_bookIds.add(book.id)) _books.add(book);
    }
  }

  /// Replace stale first-page rows instead of only merging, so website-
  /// side additions/deletions propagate while page-2+ rows the user has
  /// already loaded are preserved.
  void _applyFirstPage(List<Book> books) {
    final laterPages = _books
        .where((book) => !_firstPageIds.contains(book.id))
        .toList();
    _books.clear();
    _bookIds.clear();
    _firstPageIds.clear();
    for (final book in books) {
      if (_bookIds.add(book.id)) {
        _books.add(book);
        _firstPageIds.add(book.id);
      }
    }
    _merge(laterPages);
    state = state.copyWith(
      books: List.of(_books),
      // Do not trust the list page's book count here — it is stale
      // (the site's own count disagrees with the rendered cards).
      // A non-empty first page means page 2 may exist; the JSON
      // endpoint's totalPages arbitrates from page 2 on.
      hasMore: books.isNotEmpty,
      nextPage: 2,
    );
  }

  void _fail(String message) {
    state = state.copyWith(error: message, isLoading: false);
  }
}

final booklistDetailControllerProvider = NotifierProvider.autoDispose
    .family<BooklistDetailController, BooklistDetailState, BooklistDetailArgs>(
      BooklistDetailController.new,
    );
