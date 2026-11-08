import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

import '../../l10n/app_localizations.dart';
import '../../models/display_book.dart';
import '../../providers/auth_provider.dart';
import '../../providers/zlibrary_provider.dart';
import '../../routes/app_routes.dart';
import '../../services/challenge_html_cache.dart';
import '../../services/booklist_html_cache.dart';
import '../../services/wall_cookie_bridge.dart';
import '../../services/webview_challenge_solver.dart';
import '../../widgets/book_list_tile.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/gradient_app_bar.dart';
import '../../widgets/loading_widget.dart';

/// Arguments for BooklistDetailScreen.
class BooklistDetailArgs {
  final Booklist booklist;

  const BooklistDetailArgs({required this.booklist});
}

/// Books inside one booklist. The last-known first page is painted from
/// a parsed Hive cache (or the list page preview as a cold-cache fallback),
/// then the detail page is always revalidated in the background so changes
/// made on the Z-Library website are picked up. Page 1 comes from the detail page's own HTML (`<z-bookcard>`
/// elements, via `ZLibraryApi.getBooklistDetailBooks`): the site
/// renders the first page into the document and its JSON endpoint
/// only serves page 2 and up (`GET /papi/booklist/{id}/get-books/{page}`,
/// numeric id — asking it for page 1 answers "Requested page not
/// found", verified on device 2026-11-07). Tapping a book opens its
/// detail page; the books carry their hash (first segment of the card
/// `href`), so the detail loads fully.
class BooklistDetailScreen extends ConsumerStatefulWidget {
  final BooklistDetailArgs args;

  const BooklistDetailScreen({super.key, required this.args});

  @override
  ConsumerState<BooklistDetailScreen> createState() =>
      _BooklistDetailScreenState();
}

class _BooklistDetailScreenState extends ConsumerState<BooklistDetailScreen> {
  final ScrollController _scrollController = ScrollController();
  final List<Book> _books = [];
  // Keep membership checks O(1) while pages are appended. Rebuilding a Set
  // from the full list for every page made long lists increasingly expensive.
  final Set<int> _bookIds = <int>{};
  // IDs currently represented by the server-rendered first page. On a
  // revalidation, replace this slice while retaining already-loaded page 2+.
  final Set<int> _firstPageIds = <int>{};
  int _nextPage = 1;
  bool _hasMore = true;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFirst());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _isLoadingMore || _isLoading || _hasError) return;
    if (_scrollController.position.extentAfter < 300) {
      _loadPage(_nextPage);
    }
  }

  Future<void> _loadFirst() async {
    final preview = widget.args.booklist.previewBooks;
    final list = widget.args.booklist;
    // Keep the same account partition for cache reads and writes.
    final accountId = ref.read(authProvider).user?.id ?? 'signed-out';

    // Page 1 is cached independently of the booklist-list preview. The
    // preview belongs to the (possibly stale) list-page response and must
    // never prevent us from reading a newer detail-page cache.
    final cachedPage = BooklistHtmlCache.getBooksPage(
      list.url,
      1,
      accountId: accountId,
    );
    final cachedHtml = cachedPage == null
        ? BooklistHtmlCache.get(list.url, accountId: accountId)
        : null;
    final cachedHtmlBooks = cachedHtml != null && !_isChallengeHtml(cachedHtml)
        ? parseBooklistDetailBooks(
            cachedHtml,
            baseUrl: Uri.parse(list.url).origin,
          )
        : null;
    final hasCachedHtml = cachedHtml != null && !_isChallengeHtml(cachedHtml);
    final initialBooks = cachedPage ??
        (hasCachedHtml ? (cachedHtmlBooks ?? const <Book>[]) : preview);
    final hasLocalSnapshot = cachedPage != null || hasCachedHtml || preview.isNotEmpty;

    setState(() {
      _isLoading = !hasLocalSnapshot;
      _isLoadingMore = false;
      _hasError = false;
      _books.clear();
      _bookIds.clear();
      _firstPageIds.clear();
      // Page 1 comes from detail HTML; JSON pagination starts at 2.
      _nextPage = 2;
      _hasMore = true;
    });

    if (hasLocalSnapshot) {
      // Paint cached data immediately (including a cached empty booklist). Even when the old list count says
      // there are no more books, always revalidate: a user may have added
      // books on the Z-Library website since this Booklist object was made.
      _applyDetailBooks(initialBooks, replaceFirstPage: true);
      setState(() => _isLoadingMore = true);
      await _loadDetailPage(background: true, accountId: accountId);
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
          _isLoading = false;
        });
      }
      return;
    }

    await _loadDetailPage(accountId: accountId);
    if (mounted) {
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  /// First page: the detail page's own HTML, parsed by the plugin
  /// (the site renders page 1 into the document; its JSON endpoint
  /// only serves page 2+). Dio fast path first; on the browser-check
  /// wall, the WebView solver (the booklists screen's pattern).
  /// In background mode a failure is silent — the cached/preview books
  /// already on screen stay available.
  Future<void> _loadDetailPage({
    bool background = false,
    String? accountId,
  }) async {
    final api = ref.read(zlibraryApiProvider);
    final list = widget.args.booklist;
    try {
      final response = await api.getBooklistDetailBooks(list);
      if (!mounted) return;
      if (response.success && response.data != null) {
        // Persist the parsed first page so the next visit can paint it
        // immediately without depending on the booklist-list preview.
        BooklistHtmlCache.storeBooksPage(
          list.url,
          1,
          response.data!,
          accountId: accountId,
        );
        _applyDetailBooks(response.data!, replaceFirstPage: true);
        return;
      }
      if (_isChallengeError(response.error)) {
        await _loadDetailViaSolver(
          response.error ?? 'Failed to load booklist',
          background: background,
          accountId: accountId,
        );
        return;
      }
      if (background) {
        // Silent: the preview books stay, and scrolling can still
        // try the JSON pages (page 2+) — only the detail HTML failed.
      } else {
        _applyDetailFailure(response.error ?? 'Failed to load booklist');
      }
    } catch (e) {
      if (!mounted) return;
      if (background) {
        // Silent, same as above.
      } else {
        _applyDetailFailure(e.toString());
      }
    }
  }

  void _applyDetailBooks(
    List<Book> books, {
    bool replaceFirstPage = false,
  }) {
    setState(() {
      if (replaceFirstPage) {
        // Replace stale first-page rows instead of only merging. This lets
        // website-side additions/deletions propagate while preserving any
        // page-2+ rows already loaded by the user.
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
        for (final book in laterPages) {
          if (_bookIds.add(book.id)) _books.add(book);
        }
      } else {
        for (final book in books) {
          if (_bookIds.add(book.id)) _books.add(book);
        }
      }
      final total = widget.args.booklist.count;
      _hasMore = total == null ? books.isNotEmpty : _books.length < total;
      _nextPage = 2;
    });
  }

  void _applyDetailFailure(String message) {
    setState(() {
      _hasError = true;
      _errorMessage = message;
    });
  }

  /// Fetch the detail page through the WebView challenge solver and
  /// parse it with the plugin's [parseBooklistDetailBooks]. The
  /// session cookies go into the WebView's CookieManager first when
  /// the user is signed in (an own list's page needs them; a public
  /// page loads the same either way). A failure here reports the fast
  /// path's original error, so the retry button re-runs the whole
  /// fast-then-solver sequence. In background mode (carousel top-up)
  /// a failure is silent — the preview books stay on screen.
  Future<void> _loadDetailViaSolver(
    String originalError, {
    bool background = false,
    String? accountId,
  }) async {
    final list = widget.args.booklist;
    final url = list.url;
    final user = ref.read(authProvider).user;
    final userKey = user?.remixUserkey;
    if (user != null && userKey != null && userKey.isNotEmpty) {
      await _installSessionCookies(user.id, userKey, url);
    }
    var html = ChallengeHtmlCache.get(url);
    if (html != null && _isChallengeHtml(html)) {
      // A stale challenge page must not short-circuit the solve.
      html = null;
    }
    html ??= await WebviewChallengeSolver.fetchHtmlAfterChallenge(url);
    if (!mounted) return;
    if (html == null || html.isEmpty || _isChallengeHtml(html)) {
      if (background) {
        // Silent: the preview books stay, and scrolling can still
        // try the JSON pages (page 2+) — only the detail HTML failed.
      } else {
        _applyDetailFailure(originalError);
      }
      return;
    }
    // The solve earned wall-clearance cookies — hand them to Dio so
    // the next HTML load skips the solver. The solved page also goes
    // into the persistent cache so the next open paints it instantly,
    // under the same account partition as the read.
    await bridgeWallCookies(ref.read(zlibraryApiProvider), url);
    BooklistHtmlCache.store(url, html, accountId: accountId);
    final books = parseBooklistDetailBooks(
      html,
      baseUrl: Uri.parse(url).origin,
    );
    BooklistHtmlCache.storeBooksPage(
      url,
      1,
      books,
      accountId: accountId,
    );
    _applyDetailBooks(books, replaceFirstPage: true);
  }

  /// The plugin's short error for a browser-check wall
  /// ('HTTP 503: browser check page'), plus the older shapes a wall can
  /// surface as, so the solver fallback triggers on any of them.
  bool _isChallengeError(String? error) {
    if (error == null) return false;
    final lower = error.toLowerCase();
    return lower.contains('browser check') ||
        lower.contains('checking your browser') ||
        lower.contains('ddos-guard') ||
        lower.contains('cf_blocked') ||
        lower.contains('cf-challenge');
  }

  /// The solver only completes on real pages, but a cached page can be
  /// a stale challenge page — never parse one as an (empty) booklist
  /// page.
  bool _isChallengeHtml(String html) =>
      WebviewChallengeSolver.isChallengeHtml(html);

  /// Install the `remix_userid` / `remix_userkey` session into the
  /// WebView's CookieManager for the detail page's host (the reader's
  /// pattern — the manager is global on Android, so the solver's
  /// headless WebView sees them). Never put the keys in a URL.
  Future<void> _installSessionCookies(
    String userId,
    String userKey,
    String pageUrl,
  ) async {
    final uri = Uri.tryParse(pageUrl);
    if (uri == null || uri.host.isEmpty) return;
    final manager = CookieManager.instance();
    final url = WebUri('https://${uri.host}/');
    await manager.setCookie(
      url: url,
      name: 'remix_userid',
      value: userId,
      isSecure: true,
      isHttpOnly: true,
    );
    await manager.setCookie(
      url: url,
      name: 'remix_userkey',
      value: userKey,
      isSecure: true,
      isHttpOnly: true,
    );
  }

  /// Load-more for JSON pages (2 and up). Page 1 never comes through
  /// here — it is the detail HTML (see [_loadDetailPage]). A cached
  /// JSON page paints first (merged by id, like the preview), then
  /// the network revalidates it; a failed refresh just ends the list
  /// with the cached rows still on screen.
  Future<void> _loadPage(int page) async {
    final api = ref.read(zlibraryApiProvider);
    final list = widget.args.booklist;
    final accountId = ref.read(authProvider).user?.id ?? 'signed-out';
    final cachedPage = BooklistHtmlCache.getBooksPage(
      list.url,
      page,
      accountId: accountId,
    );
    setState(() {
      _isLoadingMore = true;
      if (cachedPage != null) {
        for (final book in cachedPage) {
          if (_bookIds.add(book.id)) _books.add(book);
        }
      }
    });
    try {
      // JSON pages start at 2 (page 1 comes from the detail HTML);
      // the key is the numeric list id.
      final response = await api.getBooklistBooks(list.id, page: page);
      if (!mounted) return;
      if (response.success && response.data != null) {
        final data = response.data!;
        BooklistHtmlCache.storeBooksPage(
          list.url,
          page,
          data.books,
          accountId: accountId,
        );
        if (!mounted) return;
        setState(() {
          // Merge by id: the cached page and the fresh page carry
          // the same books — adding both would duplicate the rows.
          for (final book in data.books) {
            if (_bookIds.add(book.id)) _books.add(book);
          }
          _hasMore = page < data.totalPages;
          _nextPage = page + 1;
          _isLoadingMore = false;
        });
      } else {
        // A failed later page just ends the list; the books already
        // shown stay.
        setState(() {
          _isLoadingMore = false;
          _hasMore = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
        _hasMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final booklist = widget.args.booklist;

    return Scaffold(
      appBar: GradientAppBar(title: booklist.name),
      body: Column(
        children: [
          // List context header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.collections_bookmark_outlined,
                      color: cs.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        booklist.name,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (booklist.count != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        l10n
                            .get('booklist_book_count')
                            .replaceAll(
                              '{count}',
                              booklist.count.toString(),
                            ),
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
                if (booklist.author.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    booklist.author,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (booklist.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    booklist.description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          // Results
          Expanded(
            child: _isLoading
                ? LoadingWidget(message: l10n.get('loading'))
                : _hasError
                    ? EmptyState(
                        icon: Icons.error_outline,
                        title: l10n.get('error'),
                        message: _errorMessage,
                        action: FilledButton(
                          onPressed: _loadFirst,
                          child: Text(l10n.get('retry')),
                        ),
                      )
                    : _books.isEmpty
                        ? EmptyState(
                            icon: Icons.collections_bookmark_outlined,
                            title: l10n.get('no_booklist_books'),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadFirst,
                            child: ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              itemCount:
                                  _books.length + (_isLoadingMore ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index >= _books.length) {
                                  return const LoadingWidget.more();
                                }
                                final book = _books[index];
                                return BookListTile(
                                  book: book.toDisplay(),
                                  showCover: true,
                                  onTap: () {
                                    Navigator.of(context).pushNamed(
                                      AppRoutes.bookDetail,
                                      arguments: book,
                                    );
                                  },
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
