import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/zlibrary_provider.dart';
import '../../routes/app_routes.dart';
import '../../services/challenge_html_cache.dart';
import '../../services/webview_challenge_solver.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/gradient_app_bar.dart';
import '../../widgets/loading_widget.dart';
import 'booklist_detail_screen.dart';

enum _BooklistTab { mine, discover }

/// Booklists, read-only v1: the signed-in user's own booklists and
/// public booklists to discover, with search on both. Tapping a list
/// opens its books. Creating a booklist or adding books to one is NOT
/// wired — those write endpoints have not been confirmed yet.
///
/// List pages are the site's HTML (`/booklists`, `/booklists/my`),
/// parsed by the plugin. The mirror walls Dio on those page routes
/// with a 503 browser-check page, so a failed Dio load falls back to
/// the WebView challenge solver (the Anna pattern) for the same page.
class BooklistsScreen extends ConsumerStatefulWidget {
  const BooklistsScreen({super.key});

  @override
  ConsumerState<BooklistsScreen> createState() => _BooklistsScreenState();
}

class _BooklistsScreenState extends ConsumerState<BooklistsScreen> {
  static const int _pageSize = 10;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final List<Booklist> _lists = [];
  _BooklistTab _tab = _BooklistTab.mine;
  int _nextPage = 1;
  bool _hasMore = true;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasError = false;
  String _errorMessage = '';
  bool _loggedIn = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFirst());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _isLoadingMore || _isLoading || _hasError) return;
    if (_scrollController.position.extentAfter < 300) {
      _loadPage(_nextPage);
    }
  }

  void _switchTab(_BooklistTab tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    _loadFirst();
  }

  Future<void> _loadFirst() async {
    if (ref.read(authProvider).user == null) {
      setState(() {
        _loggedIn = false;
        _isLoading = false;
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _hasError = false;
      _lists.clear();
      _nextPage = 1;
      _hasMore = true;
    });
    await _loadPage(1);
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPage(int page) async {
    final api = ref.read(zlibraryApiProvider);
    final query = _searchController.text.trim();
    if (page > 1) {
      setState(() => _isLoadingMore = true);
    }
    try {
      final response = _tab == _BooklistTab.mine
          ? await api.searchMyBooklists(query: query, page: page)
          : await api.searchPublicBooklists(
              query: query,
              order: 'popular',
              page: page,
            );
      if (!mounted) return;
      if (response.success && response.data != null) {
        _applyPage(response.data!, page);
        return;
      }
      // The fast Dio path failed. When the mirror answered with its
      // browser-check wall, fetch the same list page through the WebView
      // challenge solver instead (the Anna pattern): a real browser
      // engine passes the check and hands back the rendered HTML, which
      // the plugin's parser turns into the same page model. The fallback
      // reports its own failure; on success this returns early.
      if (_isChallengeError(response.error)) {
        await _loadPageViaSolver(
          page,
          query,
          response.error ?? 'Failed to load booklists',
        );
        return;
      }
      _applyPageFailure(page, response.error ?? 'Failed to load booklists');
    } catch (e) {
      if (!mounted) return;
      _applyPageFailure(page, e.toString());
    }
  }

  void _applyPage(BooklistsPage data, int page) {
    setState(() {
      _lists.addAll(data.lists);
      // The site pages at 10 lists; a short page ends the list.
      // A parsed page count (0 = unknown) is the second signal.
      _hasMore =
          data.lists.length >= _pageSize &&
          (data.totalPages <= 0 || page < data.totalPages);
      _nextPage = page + 1;
      _isLoadingMore = false;
    });
  }

  void _applyPageFailure(int page, String message) {
    setState(() {
      _isLoadingMore = false;
      if (page == 1) {
        _hasError = true;
        _errorMessage = message;
      } else {
        _hasMore = false;
      }
    });
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

  /// Fetch one list page through the WebView challenge solver and parse
  /// it with the plugin's [parseBooklistsPage]. The own-lists page needs
  /// the login session, so the session cookies go into the WebView's
  /// CookieManager first (the reader's pattern — the manager is global
  /// on Android, so the solver's headless WebView sees them). Discover
  /// is anonymous and needs no cookies. A failure here reports the fast
  /// path's original error, so the retry button re-runs the whole
  /// fast-then-solver sequence.
  Future<void> _loadPageViaSolver(
    int page,
    String query,
    String originalError,
  ) async {
    final api = ref.read(zlibraryApiProvider);
    final url = api.booklistsPageUrl(
      mine: _tab == _BooklistTab.mine,
      query: query,
      order: _tab == _BooklistTab.mine ? null : 'popular',
      page: page,
    );
    if (_tab == _BooklistTab.mine) {
      final user = ref.read(authProvider).user;
      final userKey = user?.remixUserkey;
      if (user == null || userKey == null || userKey.isEmpty) {
        // The session key is gone (but the screen's login gate already
        // passed) — show the login prompt instead of a logged-out page.
        if (!mounted) return;
        setState(() => _loggedIn = false);
        _applyPageFailure(page, originalError);
        return;
      }
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
      _applyPageFailure(page, originalError);
      return;
    }
    _applyPage(
      parseBooklistsPage(html, baseUrl: Uri.parse(url).origin),
      page,
    );
  }

  /// Install the `remix_userid` / `remix_userkey` session into the
  /// WebView's CookieManager for the list page's host (the reader's
  /// pattern, minus the reader-subdomain handling — list pages live on
  /// the mirror host itself). Never put the keys in a URL.
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

  /// The solver only completes on real pages, but a cached page can be a
  /// stale challenge page — never parse one as an (empty) booklist page.
  /// Uses the solver's own detector, with the title pulled out of the
  /// HTML (the solver checks the title for 'checking your browser').
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: GradientAppBar(title: l10n.get('booklists')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<_BooklistTab>(
                segments: [
                  ButtonSegment(
                    value: _BooklistTab.mine,
                    label: Text(l10n.get('my_booklists')),
                  ),
                  ButtonSegment(
                    value: _BooklistTab.discover,
                    label: Text(l10n.get('discover_booklists')),
                  ),
                ],
                selected: {_tab},
                onSelectionChanged: (selected) => _switchTab(selected.first),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l10n.get('search_booklists'),
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          _loadFirst();
                        },
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _loadFirst(),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: _isLoading
                ? LoadingWidget(message: l10n.get('loading'))
                : !_loggedIn
                    ? EmptyState(
                        icon: Icons.login_rounded,
                        title: l10n.get('login_to_view_booklists'),
                        action: FilledButton(
                          onPressed: () => Navigator.of(
                            context,
                          ).pushNamed(AppRoutes.login),
                          child: Text(l10n.get('login')),
                        ),
                      )
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
                        : _lists.isEmpty
                            ? EmptyState(
                                icon:
                                    Icons.collections_bookmark_outlined,
                                title: l10n.get('no_booklists'),
                              )
                            : RefreshIndicator(
                                onRefresh: _loadFirst,
                                child: ListView.separated(
                                  controller: _scrollController,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  itemCount:
                                      _lists.length +
                                      (_isLoadingMore ? 1 : 0),
                                  separatorBuilder: (context, index) =>
                                      const Divider(height: 1, indent: 72),
                                  itemBuilder: (context, index) {
                                    if (index >= _lists.length) {
                                      return const Padding(
                                        padding: EdgeInsets.all(16),
                                        child: Center(
                                          child:
                                              CircularProgressIndicator(),
                                        ),
                                      );
                                    }
                                    final list = _lists[index];
                                    return _BooklistRow(
                                      list: list,
                                      onTap: () => Navigator.of(context)
                                          .pushNamed(
                                            AppRoutes.booklistDetail,
                                            arguments: BooklistDetailArgs(
                                              booklist: list,
                                            ),
                                          ),
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

class _BooklistRow extends StatelessWidget {
  final Booklist list;
  final VoidCallback onTap;

  const _BooklistRow({required this.list, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final meta = [
      if (list.author.isNotEmpty) list.author,
      if (list.count != null)
        l10n
            .get('booklist_book_count')
            .replaceAll('{count}', list.count.toString()),
      if (list.views.isNotEmpty) list.views,
    ].join(' · ');
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 40,
          height: 56,
          child: list.coverUrl.isEmpty
              ? Container(
                  color: cs.primaryContainer,
                  child: Icon(
                    Icons.collections_bookmark_outlined,
                    color: cs.onPrimaryContainer,
                  ),
                )
              : Image.network(
                  list.coverUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: cs.primaryContainer,
                    child: Icon(
                      Icons.collections_bookmark_outlined,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
        ),
      ),
      title: Text(
        list.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (meta.isNotEmpty)
            Text(
              meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          if (list.description.isNotEmpty)
            Text(
              list.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
        ],
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: cs.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}
