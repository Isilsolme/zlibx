import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/zlibrary_provider.dart';
import '../../routes/app_routes.dart';
import '../../services/challenge_html_cache.dart';
import '../../services/booklist_html_cache.dart';
import '../../services/wall_cookie_bridge.dart';
import '../../services/webview_challenge_solver.dart';
import '../../widgets/booklist_row.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/gradient_app_bar.dart';
import '../../widgets/loading_widget.dart';
import 'booklist_detail_screen.dart';

enum _BooklistTab { mine, discover }

/// Booklists: the signed-in user's own booklists and public booklists
/// to discover, with search on both. Tapping a list opens its books.
/// The "my booklists" tab can create a new list (`createBooklist`).
/// Adding books to a list and deleting lists are NOT wired yet — those
/// write endpoints have not been captured.
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

  /// Generation counter: every fresh load (tab switch, search submit,
  /// retry, pull-to-refresh) bumps it, and every in-flight load
  /// carries the generation it started with. A slower response for
  /// an old tab/query is dropped instead of overwriting the current
  /// view.
  int _loadGeneration = 0;

  /// Cache partition for the current tab: the own-lists tab is
  /// account-scoped (the same URL serves another account's lists
  /// after a switch); discover is public and keyed by URL alone.
  /// Captured once per load flow and threaded through, so a store
  /// can never land under a different account than the read.
  String? get _cacheAccountId => _tab == _BooklistTab.mine
      ? (ref.read(authProvider).user?.id ?? 'signed-out')
      : null;

  /// Search lives in the AppBar (right side, mirroring the back
  /// arrow): a search icon opens the field in place of the title, a
  /// close icon exits it and clears the query.
  bool _isSearching = false;

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

  /// The search field that replaces the AppBar title while searching.
  /// Same behaviour as the old body field: submit runs the search on
  /// the current tab.
  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      autofocus: true,
      decoration: InputDecoration(
        hintText: AppLocalizations.of(context).get('search_booklists'),
        border: InputBorder.none,
        contentPadding: EdgeInsets.zero,
      ),
      style: Theme.of(context).textTheme.bodyLarge,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _loadFirst(),
    );
  }

  /// Exit search: hide the field, and clear the query (reloading the
  /// unfiltered list) when one was typed.
  void _exitSearch() {
    final hadQuery = _searchController.text.isNotEmpty;
    if (hadQuery) _searchController.clear();
    setState(() => _isSearching = false);
    if (hadQuery) _loadFirst();
  }

  Future<void> _loadFirst() async {
    if (ref.read(authProvider).user == null) {
      setState(() {
        _loggedIn = false;
        _isLoading = false;
      });
      return;
    }
    // A fresh load invalidates any in-flight load for the previous
    // tab/search; the account partition is captured once here so the
    // cache read, refresh, and solver store all use the same key.
    final generation = ++_loadGeneration;
    final accountId = _cacheAccountId;
    final api = ref.read(zlibraryApiProvider);
    final query = _searchController.text.trim();
    final url = api.booklistsPageUrl(
      mine: _tab == _BooklistTab.mine,
      query: query,
      order: _tab == _BooklistTab.mine ? null : 'popular',
      page: 1,
    );
    final cachedHtml = BooklistHtmlCache.get(url, accountId: accountId);
    if (cachedHtml != null && !_isChallengeHtml(cachedHtml)) {
      // Stale-while-revalidate: paint the last-known lists
      // instantly, then refresh page 1 in the background. A failed
      // refresh keeps the cached lists on screen (the `replace`
      // path never errors).
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _hasError = false;
        _lists.clear();
        _nextPage = 1;
        _hasMore = true;
      });
      _applyPage(
        parseBooklistsPage(cachedHtml, baseUrl: Uri.parse(url).origin),
        1,
      );
      unawaited(
        _loadPage(1, replace: true, generation: generation, accountId: accountId),
      );
      return;
    }
    setState(() {
      _isLoading = true;
      _isLoadingMore = false;
      _hasError = false;
      _lists.clear();
      _nextPage = 1;
      _hasMore = true;
    });
    await _loadPage(1, generation: generation, accountId: accountId);
    if (mounted && generation == _loadGeneration) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPage(
    int page, {
    bool replace = false,
    int? generation,
    String? accountId,
  }) async {
    // The generation subsumes the old per-tab guard: every tab
    // switch, search, and retry goes through _loadFirst, which
    // bumps it. Pagination (from scroll) rides the current one.
    final requestGeneration = generation ?? _loadGeneration;
    final requestAccountId = accountId ?? _cacheAccountId;
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
      if (!mounted || requestGeneration != _loadGeneration) return;
      if (response.success && response.data != null) {
        _applyPage(response.data!, page, replace: replace);
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
          replace: replace,
          generation: requestGeneration,
          accountId: requestAccountId,
        );
        return;
      }
      _applyPageFailure(
        page,
        response.error ?? 'Failed to load booklists',
        replace: replace,
      );
    } catch (e) {
      if (!mounted || requestGeneration != _loadGeneration) return;
      _applyPageFailure(page, e.toString(), replace: replace);
    }
  }

  void _applyPage(
    BooklistsPage data,
    int page, {
    bool replace = false,
  }) {
    setState(() {
      // A background refresh replaces the cached page instead of
      // appending to it.
      if (replace) _lists.clear();
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

  void _applyPageFailure(
    int page,
    String message, {
    bool replace = false,
  }) {
    // A background refresh (cached lists on screen) never errors:
    // the cached data stays, and the next open or pull-to-refresh
    // retries.
    if (replace) return;
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
    String originalError, {
    bool replace = false,
    int? generation,
    String? accountId,
  }) async {
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
        _applyPageFailure(page, originalError, replace: replace);
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
    if (generation != null && generation != _loadGeneration) return;
    if (html == null || html.isEmpty || _isChallengeHtml(html)) {
      _applyPageFailure(page, originalError, replace: replace);
      return;
    }
    // The solve earned wall-clearance cookies — hand them to Dio so
    // the next HTML load (this list's detail page, the next page)
    // skips the solver. The solved page also goes into the
    // persistent cache so the next open paints it instantly, under
    // the same account partition as the read.
    await bridgeWallCookies(api, url);
    BooklistHtmlCache.store(url, html, accountId: accountId);
    if (generation != null && generation != _loadGeneration) return;
    _applyPage(
      parseBooklistsPage(html, baseUrl: Uri.parse(url).origin),
      page,
      replace: replace,
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
  bool _isChallengeHtml(String html) =>
      WebviewChallengeSolver.isChallengeHtml(html);

  /// Ask for a name (and optional description), create the list on the
  /// account, then reload "my booklists" so the new list shows up.
  Future<void> _createBooklist() async {
    final l10n = AppLocalizations.of(context);
    final result = await showDialog<({String title, String description})>(
      context: context,
      builder: (context) => const _CreateBooklistDialog(),
    );
    if (result == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final response = await ref
        .read(zlibraryApiProvider)
        .createBooklist(
          title: result.title,
          description: result.description,
        );
    if (!mounted) return;
    if (response.success) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.get('booklist_created'))),
      );
      if (_tab == _BooklistTab.mine) {
        await _loadFirst();
      }
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n
                .get('booklist_create_failed')
                .replaceAll('{error}', response.error ?? ''),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: GradientAppBar(
        title: l10n.get('booklists'),
        titleWidget: _isSearching ? _buildSearchField() : null,
        actions: [
          IconButton(
            icon: Icon(
              _isSearching ? Icons.close_rounded : Icons.search_rounded,
            ),
            onPressed: _isSearching
                ? _exitSearch
                : () => setState(() => _isSearching = true),
          ),
        ],
      ),
      floatingActionButton: _tab == _BooklistTab.mine && _loggedIn
          ? FloatingActionButton.extended(
              onPressed: _createBooklist,
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.get('create_booklist')),
            )
          : null,
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
                                      return const LoadingWidget.more();
                                    }
                                    final list = _lists[index];
                                    return BooklistRow(
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

/// Name + optional description form for a new booklist. Pops a record
/// `(title, description)`, or null when cancelled.
class _CreateBooklistDialog extends StatefulWidget {
  const _CreateBooklistDialog();

  @override
  State<_CreateBooklistDialog> createState() => _CreateBooklistDialogState();
}

class _CreateBooklistDialogState extends State<_CreateBooklistDialog> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    Navigator.of(context).pop((
      title: title,
      description: _descriptionController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.get('create_booklist')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleController,
            autofocus: true,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l10n.get('booklist_title'),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(
              labelText: l10n.get('booklist_description_optional'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.get('cancel')),
        ),
        FilledButton(
          onPressed: _titleController.text.trim().isEmpty ? null : _submit,
          child: Text(l10n.get('create')),
        ),
      ],
    );
  }
}
