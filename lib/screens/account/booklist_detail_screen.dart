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

/// Books inside one booklist. Page 1 comes from the detail page's own
/// HTML (`<z-bookcard>` elements, via
/// `ZLibraryApi.getBooklistDetailBooks`): the site renders the first
/// page into the document and its JSON endpoint only serves page 2 and
/// up (`GET /papi/booklist/{id}/get-books/{page}`, numeric id —
/// asking it for page 1 answers "Requested page not found", verified
/// on device 2026-11-07). Tapping a book opens its detail page; the
/// books carry their hash (first segment of the card `href`), so the
/// detail loads fully.
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
    setState(() {
      _isLoading = true;
      _hasError = false;
      _books.clear();
      // Page 1 comes from the detail HTML, so the JSON pages start at 2.
      _nextPage = 2;
      _hasMore = true;
    });
    await _loadDetailPage();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  /// First page: the detail page's own HTML, parsed by the plugin
  /// (the site renders page 1 into the document; its JSON endpoint
  /// only serves page 2+). Dio fast path first; on the browser-check
  /// wall, the WebView solver (the booklists screen's pattern).
  Future<void> _loadDetailPage() async {
    final api = ref.read(zlibraryApiProvider);
    final list = widget.args.booklist;
    try {
      final response = await api.getBooklistDetailBooks(list);
      if (!mounted) return;
      if (response.success && response.data != null) {
        _applyDetailBooks(response.data!);
        return;
      }
      if (_isChallengeError(response.error)) {
        await _loadDetailViaSolver(
          response.error ?? 'Failed to load booklist',
        );
        return;
      }
      _applyDetailFailure(response.error ?? 'Failed to load booklist');
    } catch (e) {
      if (!mounted) return;
      _applyDetailFailure(e.toString());
    }
  }

  void _applyDetailBooks(List<Book> books) {
    setState(() {
      _books.addAll(books);
      // The list knows its total (quantity); a short first page means
      // there are JSON pages after it. Unknown total: assume there may
      // be more whenever the first page had books — a page-2 miss just
      // ends the list silently (see _loadPage's failure branch).
      final total = widget.args.booklist.count;
      _hasMore =
          total == null ? books.isNotEmpty : _books.length < total;
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
  /// fast-then-solver sequence.
  Future<void> _loadDetailViaSolver(String originalError) async {
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
      _applyDetailFailure(originalError);
      return;
    }
    _applyDetailBooks(
      parseBooklistDetailBooks(html, baseUrl: Uri.parse(url).origin),
    );
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
  /// page. Uses the solver's own detector, with the title pulled out
  /// of the HTML (the solver checks the title for 'checking your
  /// browser').
  bool _isChallengeHtml(String html) {
    final titleMatch = RegExp(
      r'<title[^>]*>(.*?)</title>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);
    return WebviewChallengeSolver.isChallengePage(
      title: titleMatch?.group(1) ?? '',
      bodySnippet: html,
    );
  }

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
  /// here — it is the detail HTML (see [_loadDetailPage]).
  Future<void> _loadPage(int page) async {
    final api = ref.read(zlibraryApiProvider);
    setState(() => _isLoadingMore = true);
    try {
      final list = widget.args.booklist;
      // JSON pages start at 2 (page 1 comes from the detail HTML);
      // the key is the numeric list id.
      final response = await api.getBooklistBooks(list.id, page: page);
      if (!mounted) return;
      if (response.success && response.data != null) {
        final data = response.data!;
        setState(() {
          _books.addAll(data.books);
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
                                  return const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }
                                final book = _books[index];
                                return BookListTile(
                                  book: book.toDisplay(),
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
