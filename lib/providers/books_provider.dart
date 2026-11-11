import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';
import 'package:zlibx/utils/diagnostics.dart';
import '../models/display_book.dart';
import '../services/annas_archieve.dart';
import '../services/book_detail_page_repository.dart';
import '../services/external_search.dart';
import '../services/libgen_service.dart';
import '../services/network_error.dart';
import '../services/storage_service.dart';
import 'auth_provider.dart';
import 'zlibrary_provider.dart';

// ── Search ──────────────────────────────────────────────────────────

class SearchParams {
  final String? query;
  final int? yearFrom;
  final int? yearTo;
  final List<String>? languages;
  final List<String>? extensions;
  final String? order;
  final int limit;

  SearchParams({
    this.query,
    this.yearFrom,
    this.yearTo,
    this.languages,
    this.extensions,
    this.order,
    this.limit = 20,
  });
}

class SearchState {
  final List<Book> books;
  final int currentPage;
  final int totalPages;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasSearched;
  final String? error;

  const SearchState({
    this.books = const [],
    this.currentPage = 1,
    this.totalPages = 1,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasSearched = false,
    this.error,
  });

  SearchState copyWith({
    List<Book>? books,
    int? currentPage,
    int? totalPages,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasSearched,
    String? error,
  }) {
    return SearchState(
      books: books ?? this.books,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasSearched: hasSearched ?? this.hasSearched,
      error: error,
    );
  }
}

class SearchNotifier extends Notifier<SearchState> {
  // Getter, not a `late final` field: ref.invalidate re-runs build() on
  // the SAME notifier instance and a second late-final assignment throws
  // LateInitializationError (same documented pitfall as
  // SavedBooksNotifier below).
  ZLibraryApi get _api => ref.read(zlibraryApiProvider);
  SearchParams? _lastParams;
  int _requestId = 0;

  @override
  SearchState build() {
    return const SearchState();
  }

  /// 统一取数入口，search / loadMore 共用。
  Future<ApiResponse<List<Book>>> _fetch(SearchParams params, int page) async {
    return _api.search(
      message: params.query,
      yearFrom: params.yearFrom,
      yearTo: params.yearTo,
      languages: params.languages,
      extensions: params.extensions,
      order: params.order,
      page: page,
      limit: params.limit,
    );
  }

  Future<void> search(SearchParams params) async {
    final requestId = ++_requestId;
    _lastParams = params;
    state = const SearchState(isLoading: true, hasSearched: true);

    try {
      final response = await _fetch(params, 1);
      if (requestId != _requestId) return;
      if (!response.success) {
        throw StateError(response.error ?? 'Search failed');
      }

      final totalPages = response.meta?['total_pages'] ?? 1;
      state = SearchState(
        books: response.data ?? [],
        currentPage: 1,
        totalPages: totalPages is int ? totalPages : 1,
        hasSearched: true,
      );
    } catch (e) {
      if (requestId != _requestId) return;
      state = SearchState(hasSearched: true, error: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (_lastParams == null ||
        state.isLoadingMore ||
        state.currentPage >= state.totalPages) {
      return;
    }

    final nextPage = state.currentPage + 1;
    final requestId = _requestId;
    state = state.copyWith(isLoadingMore: true);

    try {
      final response = await _fetch(_lastParams!, nextPage);
      if (requestId != _requestId) return;
      if (!response.success) {
        throw StateError(response.error ?? 'Search failed');
      }

      state = state.copyWith(
        books: [...state.books, ...response.data ?? []],
        currentPage: nextPage,
        isLoadingMore: false,
      );
    } catch (e) {
      if (requestId != _requestId) return;
      state = state.copyWith(isLoadingMore: false, error: e.toString());
    }
  }

  void reset() {
    _requestId++;
    _lastParams = null;
    state = const SearchState();
  }
}

final searchProvider =
    NotifierProvider<SearchNotifier, SearchState>(SearchNotifier.new);

// ── Book Details ────────────────────────────────────────────────────

/// autoDispose：详情页关掉后无人 watch 即释放缓存。此前常驻内存，
/// 长会话逐本累积（每本详情是全量 [Book]）；相似书链路中每一页
/// 详情始终 watch 自己的 identifier，不会产生重复请求。
///
/// 返回 `(book, relatedBooklists)`：书本体（eapi 详情 + 详情页 HTML
/// 合并进来的 卷/ISBN/IPFS/评分 字段）+ 站点详情页底部「关联书单」
/// 区块解析出的书单列表。两者来自同一次 HTML 抓取
/// （[ZLibraryApi.fetchBookDetailExtras]），不再为书单单独发请求。
final bookDetailsProvider = FutureProvider.autoDispose
    .family<({Book book, List<Booklist> relatedBooklists}), BookIdentifier>(
  (ref, identifier) async {
  final api = ref.watch(zlibraryApiProvider);
  final response = await api.getBookInfo(
    identifier.bookId,
    identifier.hashId,
    title: identifier.title,
  );
  if (!response.success) {
    throw StateError(response.error ?? 'Failed to load book details');
  }
  final book = response.data;
  if (book == null) {
    throw StateError('Book details response did not contain a book');
  }
  // Best-effort detail-page extras (volume / ISBN / IPFS / rating +
  // the related-booklists block): the eapi book does not carry them.
  // The HTML fetch runs AFTER the eapi detail loaded, so a slow or
  // walled page only delays the extra rows — the screen keeps showing
  // the eapi book meanwhile. The page sits behind the DiamWall: when
  // Dio answers the browser-check challenge, the repository
  // escalates to the WebView solver (same escalation as the
  // booklists / full-text / category HTML routes). Any failure
  // returns the eapi book unchanged with no booklists.
  final href = identifier.href ?? book.href;
  if (href == null || href.isEmpty) {
    return (book: book, relatedBooklists: const <Booklist>[]);
  }
  try {
    final user = ref.read(authProvider).user;
    final pageRepo = BookDetailPageRepository(api);
    final result = await pageRepo.fetch(
      href: href,
      userId: user?.id,
      userKey: user?.remixUserkey,
    );
    if (!result.success || result.data == null) {
      logIgnored(
        'book_details_metadata',
        StateError(result.error ?? 'book detail page failed'),
      );
      return (book: book, relatedBooklists: const <Booklist>[]);
    }
    final metadata = result.data!.metadata;
    final merged = book.copyWith(
      href: href,
      volume: metadata.volume,
      isbn10: metadata.isbn10,
      isbn13: metadata.isbn13,
      ipfsCid: metadata.ipfsCid,
      ipfsCidBlake2b: metadata.ipfsCidBlake2b,
      ratingInterest: metadata.ratingInterest,
      ratingQuality: metadata.ratingQuality,
    );
    return (
      book: merged,
      relatedBooklists: result.data!.relatedBooklists,
    );
  } catch (error) {
    logIgnored('book_details_metadata', error);
    return (book: book, relatedBooklists: const <Booklist>[]);
  }
  },
);

// ── External Search (Anna's Archive + LibGen) ────────────────────────
//
// Mirrors SearchNotifier's shape, but over a swappable external provider
// (Anna's Archive or LibGen, chosen by the search screen). Neither has
// total_pages in its HTML search results, so pagination runs until an
// empty page comes back (hasMore = the last page returned books).

class ExternalSearchState {
  final List<DisplayBook> books;
  final int currentPage;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasSearched;
  final bool hasMore;
  final String? error;

  const ExternalSearchState({
    this.books = const [],
    this.currentPage = 0,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasSearched = false,
    this.hasMore = true,
    this.error,
  });

  ExternalSearchState copyWith({
    List<DisplayBook>? books,
    int? currentPage,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasSearched,
    bool? hasMore,
    String? error,
  }) {
    return ExternalSearchState(
      books: books ?? this.books,
      currentPage: currentPage ?? this.currentPage,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasSearched: hasSearched ?? this.hasSearched,
      hasMore: hasMore ?? this.hasMore,
      error: error,
    );
  }
}

class ExternalSearchNotifier extends Notifier<ExternalSearchState> {
  // Getters / mutable fields, not `late final`: see SearchNotifier above.
  AnnasArchieve get _annasApi => ref.read(annasArchieveProvider);
  late SearchProvider _provider;
  late BookSource _source;
  String? _lastQuery;
  int _requestId = 0;

  @override
  ExternalSearchState build() {
    _provider = AnnasArchiveProvider(api: _annasApi);
    _source = BookSource.annasArchive;
    return const ExternalSearchState();
  }

  SearchProvider _providerFor(BookSource source) => source == BookSource.libgen
      ? LibgenProvider()
      : AnnasArchiveProvider(api: _annasApi);

  /// Maps a provider's BookData with the converter matching the source
  /// that produced it (Anna and LibGen both return BookData).
  DisplayBook _toDisplay(BookData book) => _source == BookSource.libgen
      ? book.toLibgenDisplayBook()
      : book.toAnnaDisplayBook();

  Future<void> search(String query, BookSource source) async {
    final requestId = ++_requestId;
    _lastQuery = query;
    _source = source;
    _provider = _providerFor(source);
    state = const ExternalSearchState(isLoading: true, hasSearched: true);

    try {
      final books = await _provider.search(SearchQuery(text: query, page: 1));
      if (requestId != _requestId) return;
      state = ExternalSearchState(
        books: books.map<DisplayBook>(_toDisplay).toList(),
        currentPage: 1,
        hasSearched: true,
        hasMore: books.isNotEmpty,
      );
    } catch (e) {
      if (requestId != _requestId) return;
      state = ExternalSearchState(
        hasSearched: true,
        error: _errorMessage(e),
      );
    }
  }

  Future<void> loadMore() async {
    if (_lastQuery == null ||
        state.isLoadingMore ||
        !state.hasMore) {
      return;
    }

    final nextPage = state.currentPage + 1;
    final requestId = _requestId;
    state = state.copyWith(isLoadingMore: true);

    try {
      final books = await _provider.search(
        SearchQuery(text: _lastQuery!, page: nextPage),
      );
      if (requestId != _requestId) return;
      state = state.copyWith(
        books: [
          ...state.books,
          ...books.map<DisplayBook>(_toDisplay),
        ],
        currentPage: nextPage,
        isLoadingMore: false,
        hasMore: books.isNotEmpty,
      );
    } catch (e) {
      if (requestId != _requestId) return;
      state = state.copyWith(
        isLoadingMore: false,
        error: _errorMessage(e),
      );
    }
  }

  void reset() {
    _requestId++;
    _lastQuery = null;
    state = const ExternalSearchState();
  }

  /// NetworkError carries a human-readable userMessage (its toString is
  /// just `NetworkError.<type>`); surface that, fall back to toString.
  static String _errorMessage(Object e) {
    if (e is NetworkError) return e.userMessage;
    return e.toString();
  }
}

final externalSearchProvider =
    NotifierProvider<ExternalSearchNotifier, ExternalSearchState>(
      ExternalSearchNotifier.new,
    );

/// Shared [AnnasArchieve] instance: its Dio (and connection pool) is
/// reused across detail and search requests instead of being rebuilt
/// per call. The service holds no per-request mutable state (its headers
/// map is only read), so sharing one instance is safe.
final annasArchieveProvider =
    Provider<AnnasArchieve>((ref) => AnnasArchieve());

// ── Anna's Archive Book Details ──────────────────────────────────────
//
// [link] is the BookData.link from a search result (relative "/md5/…"
// URL). AnnasArchieve.bookInfo throws on failure (Cloudflare block, no
// mirror, parse failure), so the provider surfaces the error as-is.
/// autoDispose：详情页关掉后无人 watch 即释放缓存；每条 link 各占一
/// 个缓存项，重度浏览否则无界增长。
final annasBookDetailsProvider =
    FutureProvider.autoDispose.family<BookInfoData, String>((ref, link) async {
      final archive = ref.watch(annasArchieveProvider);
      return archive.bookInfo(url: link);
    });

/// Shared LibGen service instance. Creating one per detail request built
/// a fresh Dio (and a fresh keep-alive HttpClient pool) every time the
/// user opened a LibGen book — the same leak pattern the search side
/// already fixed with [annasArchieveProvider].
final libgenServiceProvider =
    Provider<LibgenService>((ref) => LibgenService());

// ── LibGen Book Details ──────────────────────────────────────────────
//
// [link] is the BookData.link from a search result (an absolute
// "ads.php?md5=…" URL). LibgenService.bookInfo returns null on failure
// (no mirror, non-200, parse failure), so the provider turns that into
// a StateError for the detail page's error UI.
/// autoDispose：与 [annasBookDetailsProvider] 同理，详情页关掉即释放。
final libgenBookDetailsProvider =
    FutureProvider.autoDispose.family<BookInfoData, String>((ref, link) async {
      final info = await ref.watch(libgenServiceProvider).bookInfo(link);
      if (info == null) throw StateError('Failed to load book details');
      return info;
    });

class BookIdentifier {
  final String bookId;
  final String hashId;

  /// Book title, used only to resolve the real eapi hash when the
  /// stored hash is a webpage short hash (see `getBookInfo`).
  final String? title;

  /// The book's webpage path (`/book/{hash}/{slug}.html`) when the
  /// list response that produced this book carried it. Used only to
  /// fetch the detail-page metadata (volume / ISBN / IPFS) that the
  /// eapi does not carry; null skips that fetch silently.
  final String? href;

  BookIdentifier(this.bookId, this.hashId, {this.title, this.href});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BookIdentifier &&
        other.bookId == bookId &&
        other.hashId == hashId &&
        other.title == title &&
        other.href == href;
  }

  @override
  int get hashCode =>
      bookId.hashCode ^ hashId.hashCode ^ title.hashCode ^ href.hashCode;
}

// ── Book Lists ──────────────────────────────────────────────────────

final mostPopularBooksProvider = FutureProvider<List<Book>>((ref) async {
  final api = ref.watch(zlibraryApiProvider);
  final response = await api.getMostPopular();
  if (!response.success) {
    // Surface the failure as AsyncError so the UI shows its error/retry
    // branch — an API failure and a genuinely empty list must not look
    // identical (and only the former is retryable).
    throw StateError(response.error ?? 'Failed to load popular books');
  }
  return response.data ?? [];
});

final recommendedBooksProvider = FutureProvider<List<Book>>((ref) async {
  final api = ref.watch(zlibraryApiProvider);
  final response = await api.getUserRecommended();
  if (!response.success) {
    throw StateError(response.error ?? 'Failed to load recommendations');
  }
  return response.data ?? [];
});

/// 首页推荐：z站推荐，转为 DisplayBook 列表。
final homeRecommendedProvider = Provider<AsyncValue<List<DisplayBook>>>((ref) {
  final zlibAsync = ref.watch(recommendedBooksProvider);
  // whenData keeps loading/error states as-is: the home screen keeps its
  // error/retry entry and keeps showing the previous data while a
  // revalidation after an account switch is in flight.
  return zlibAsync
      .whenData((books) => books.map((b) => b.toDisplay()).toList());
});

final recentBooksProvider = FutureProvider<List<Book>>((ref) async {
  final api = ref.watch(zlibraryApiProvider);
  final response = await api.getRecently();
  if (!response.success) {
    throw StateError(response.error ?? 'Failed to load recent books');
  }
  return response.data ?? [];
});

// ── Saved Books ─────────────────────────────────────────────────────

class SavedBooksNotifier extends Notifier<AsyncValue<List<Book>>> {
  // Getters, not `late final` fields: ref.invalidate (account switch, line
  // change, logout) re-runs build() on the SAME notifier instance, and a
  // second assignment to a late final throws LateInitializationError, which
  // left the provider in an error state and blanked the library screen.
  ZLibraryApi get _api => ref.read(zlibraryApiProvider);
  StorageService get _storage => ref.read(storageServiceProvider);

  @override
  AsyncValue<List<Book>> build() {
    loadSavedBooks();
    return const AsyncValue.loading();
  }

  /// 全量拉取收藏列表。[silent] 为 true 时是后台静默 revalidate：不
  /// 置 loading 态，失败时保留已有数据（只在尚无数据时才报 error），
  /// 收藏/取消后的后台对账就用它，列表不闪一下 loading。
  Future<void> loadSavedBooks({bool silent = false}) async {
    // build() 直接调这里，而首次 build 时 state 还不存在：读 `state`
    // 会抛 StateError（'Tried to read the state of an uninitialized
    // provider'），抛在 try 之前、第一个 await 之前，整个拉取直接
    // 夭折、provider 永远卡在 loading——冷启动图书馆无限转圈就是
    // 这么来的。`stateOrNull` 在未初始化时返回 null 而不抛，正是
    // Riverpod 给 build 期读 state 的写法；初始化之后和 `state` 等价。
    final hadData = stateOrNull?.valueOrNull != null;
    if (!silent) state = const AsyncValue.loading();

    try {
      const pageSize = 100;
      final books = <Book>[];
      final seen = <int>{};
      for (var page = 1; page <= 100; page++) {
        final response = await _api.getUserSaved(page: page, limit: pageSize);
        if (!response.success) {
          throw StateError(response.error ?? 'Could not load saved books');
        }
        final batch = response.data ?? <Book>[];
        final before = seen.length;
        for (final book in batch) {
          if (seen.add(book.id)) books.add(book);
        }
        final totalPages = int.tryParse(
          response.meta?['total_pages']?.toString() ?? '',
        );
        if ((totalPages != null && page >= totalPages) ||
            batch.length < pageSize ||
            seen.length == before) {
          break;
        }
      }
      state = AsyncValue.data(books);
    } catch (e, stack) {
      // 静默对账失败：已有列表是乐观更新后的正确内容，别用 error 覆盖它。
      if (silent && hadData) return;
      state = AsyncValue.error(e, stack);
    }
  }

  /// 后台静默对账：与服务端对一遍，不动 loading、不覆盖已有列表。
  Future<void> _revalidateSilently() => loadSavedBooks(silent: true);

  /// 本地乐观更新：当前列表已有数据时才改 state；尚无数据（首屏还
  /// 在加载）时返回 false，调用方改走全量 [loadSavedBooks]。
  bool _optimisticAdd(Book book) {
    final current = state.valueOrNull;
    if (current == null) return false;
    if (current.any((b) => b.id == book.id)) return true;
    // 服务端列表是新收藏在前，乐观插入放队首，后台对账再纠正顺序。
    state = AsyncValue.data([book, ...current]);
    return true;
  }

  bool _optimisticRemove(String bookId) {
    final current = state.valueOrNull;
    if (current == null) return false;
    if (!current.any((b) => b.id.toString() == bookId)) return true;
    state = AsyncValue.data(
      current.where((b) => b.id.toString() != bookId).toList(),
    );
    return true;
  }

  /// 收藏一本书。[book] 是详情页已有的完整 [Book]（经
  /// `DisplayBook.asZLibBook` 取到）：有它才能本地乐观插入；拿不到
  /// 时退回全量拉取。成功后立即返回，后台静默对账。
  Future<bool> saveBook(String bookId, {Book? book}) async {
    try {
      final response = await _api.saveBook(bookId);
      if (!response.success) return false;
      await _storage.addFavorite(bookId);
      if (book != null && _optimisticAdd(book)) {
        unawaited(_revalidateSilently());
      } else {
        await loadSavedBooks();
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 取消收藏一本书。[reload] 为 false 时不刷新列表（批量场景由调用方统一刷新）。
  Future<bool> unsaveBook(String bookId, {bool reload = true}) async {
    try {
      final response = await _api.unsaveUserBook(bookId);
      if (!response.success) return false;
      await _storage.removeFavorite(bookId);
      if (_optimisticRemove(bookId)) {
        if (reload) unawaited(_revalidateSilently());
      } else {
        if (reload) await loadSavedBooks();
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 批量取消收藏：逐本处理（每本都已乐观移除），全部完成后只静默
  /// 对账一次，不闪 loading。
  /// 返回成功取消的数量。
  Future<int> unsaveBooks(Iterable<String> bookIds) async {
    var removed = 0;
    for (final id in bookIds) {
      if (await unsaveBook(id, reload: false)) removed++;
    }
    await loadSavedBooks(silent: true);
    return removed;
  }
}

final savedBooksProvider =
    NotifierProvider<SavedBooksNotifier, AsyncValue<List<Book>>>(
      SavedBooksNotifier.new,
    );

// ── Downloaded Books ────────────────────────────────────────────────

/// 云端下载历史（账号维度，包含其他设备 / 网页端产生的下载记录）。
///
/// 此前是一个一次性 FutureProvider：只拉第 1 页（limit 100）且整个
/// 进程生命周期只拉一次，页面也没有任何刷新入口——超过 100 条后，
/// 更早的记录（其他设备下的书）永远留在第 2 页之后不出现；新记录
/// 也要重启 app 才能看到。现在与 [SavedBooksNotifier] 同构：全量
/// 翻页拉取 + 可静默对账，页面打开 / 下拉时都能拿到最新云端列表。
class DownloadedBooksNotifier extends Notifier<AsyncValue<List<Book>>> {
  // Getter, not a `late final` field: ref.invalidate (account switch,
  // line change, logout) re-runs build() on the SAME notifier instance,
  // and a second assignment to a late final throws LateInitializationError
  // — see SavedBooksNotifier above.
  ZLibraryApi get _api => ref.read(zlibraryApiProvider);

  @override
  AsyncValue<List<Book>> build() {
    loadDownloadedBooks();
    return const AsyncValue.loading();
  }

  /// 全量拉取云端下载历史。服务端默认按下载时间倒序（最新在前），
  /// 翻页按序拼接即保持该顺序，UI 的"按日期"排序仍等于服务端顺序。
  /// [silent] 为 true 时是后台静默对账：不置 loading 态，失败时保留
  /// 已有数据（只在尚无数据时才报 error）——页面打开 / 下拉刷新用
  /// 它，列表不闪一下 loading。
  Future<void> loadDownloadedBooks({bool silent = false}) async {
    // build() 直接调这里，而首次 build 时 state 还不存在：读 `state`
    // 会抛 StateError（见 SavedBooksNotifier 上的注释），`stateOrNull`
    // 在未初始化时返回 null 而不抛，正是 Riverpod 给 build 期读 state
    // 的写法。
    final hadData = stateOrNull?.valueOrNull != null;
    if (!silent) state = const AsyncValue.loading();

    try {
      const pageSize = 100;
      final books = <Book>[];
      final seen = <int>{};
      for (var page = 1; page <= 100; page++) {
        final response = await _api.getUserDownloaded(
          page: page,
          limit: pageSize,
        );
        if (!response.success) {
          throw StateError(
            response.error ?? 'Could not load download history',
          );
        }
        final batch = response.data ?? <Book>[];
        final before = seen.length;
        for (final book in batch) {
          if (seen.add(book.id)) books.add(book);
        }
        final totalPages = int.tryParse(
          response.meta?['total_pages']?.toString() ?? '',
        );
        // 终止条件故意不用 batch.length < pageSize：镜像可能把 limit
        // 压到比 100 小，那只说明本页比请求的短，不代表没有下一页。
        // "到达 total_pages"或"整页都是重复（没有新增）"才可靠——
        // 后者同时兜住了服务端忽略 page 参数的情况（每页回同一批）。
        if ((totalPages != null && page >= totalPages) ||
            seen.length == before) {
          break;
        }
      }
      state = AsyncValue.data(books);
    } catch (e, stack) {
      // 静默对账失败：已有列表是最后已知的好数据，别用 error 覆盖它。
      if (silent && hadData) return;
      state = AsyncValue.error(e, stack);
    }
  }
}

final downloadedBooksProvider =
    NotifierProvider<DownloadedBooksNotifier, AsyncValue<List<Book>>>(
      DownloadedBooksNotifier.new,
    );

/// Resolved detail covers for cloud history rows, keyed by book id.
///
/// The downloaded endpoint's cover value never loads, so a row whose
/// listed cover fails falls back to the detail endpoint's cover — the
/// same cover the detail page shows once its fetch completes.
class HistoryCoverNotifier extends Notifier<Map<String, String>> {
  final Set<String> _attempted = <String>{};

  @override
  Map<String, String> build() => const <String, String>{};

  Future<void> resolveCover(Book book) async {
    final id = book.id.toString();
    if (book.id == 0 || _attempted.contains(id)) return;
    _attempted.add(id);
    try {
      final response = await ref.read(zlibraryApiProvider).getBookInfo(
            id,
            book.hash ?? '',
            title: book.title,
          );
      final cover = response.data?.cover;
      if (response.success && cover != null && cover.isNotEmpty) {
        state = {...state, id: cover};
      }
    } catch (error) {
      // No usable cover: keep the placeholder. _attempted prevents
      // retry loops when the row rebuilds.
      logIgnored('history_cover', error);
    }
  }
}

final historyCoverProvider =
    NotifierProvider<HistoryCoverNotifier, Map<String, String>>(
      HistoryCoverNotifier.new,
    );

// ── Favorites Check ─────────────────────────────────────────────────

/// autoDispose：每本书一个缓存项；详情页关掉即释放，切换账号时
/// [invalidateAccountScopedProviders] 本来就会整体失效它。
final isBookFavoritedProvider = FutureProvider.autoDispose.family<bool, String>((
  ref,
  bookId,
) async {
  final storage = ref.watch(storageServiceProvider);
  return await storage.isFavorite(bookId);
});
