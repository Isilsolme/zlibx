import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';
import '../../providers/article_search_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/books_provider.dart';
import '../../providers/fulltext_search_provider.dart';
import '../../widgets/book_card.dart';
import '../../widgets/book_list_tile.dart';
import 'widgets/active_filter_chips.dart';
import 'widgets/article_tile.dart';
import 'widgets/empty_query_view.dart';
import 'widgets/fulltext_hit_tile.dart';
import 'widgets/search_mode_selector.dart';
import 'widgets/search_bar_field.dart';
import 'widgets/search_skeleton_grid.dart';
import 'widgets/search_suggestions_view.dart';
import 'widgets/source_selector.dart';
import '../reader/reader_screen.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/gradient_app_bar.dart';
import '../../widgets/update_dialog.dart';
import '../../models/display_book.dart';
import '../../routes/app_routes.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../constants/search_filters.dart';
import '../../services/google_suggest_api.dart';
import '../../providers/update_provider.dart';
import '../../services/hive_service.dart';

import '../../utils/app_log.dart';
import '../../utils/app_snack.dart';
const _recentSearchesKey = 'recent_search_keywords';
const _recentSearchesLimit = 12;

class SearchScreen extends ConsumerStatefulWidget {
  final BookSource? initialSource;

  const SearchScreen({super.key, this.initialSource});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

/// Orchestrator only: owns the query state (controller, debounce,
/// suggestions), the applied filters and the recent-searches store, and
/// wires the zero-state presentation widgets from `widgets/` together.
class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  // ── Filters (applied immediately, edited in a bottom sheet) ──
  String _selectedLanguage = 'all';
  String _selectedOrder = 'default';
  String _selectedExtension = 'all';

  // ── z站 search mode: 通用 / 文章 / 全文检索. The full-text-only
  // extras (words/phrase match + exact flag) live below; their
  // default is `words` / off (the site's working default,
  // device-proven 2026-11-11). The order default differs per mode
  // ('popular' for full-text, 'default' for general and article
  // search) — see _switchMode.
  SearchMode _mode = SearchMode.general;
  String _fullTextMatchType = 'words';
  bool _fullTextExact = false;

  bool _isListView = false;
  bool _isQueryEmpty = true;
  List<String> _recentSearches = [];

  // Debounced Google suggestions while typing.
  final _suggestApi = GoogleSuggestApi();
  Timer? _suggestDebounce;
  List<String> _suggestions = [];
  bool _suggestionsLoading = false;
  bool _showSuggestions = false;
  String _lastSubmittedQuery = '';

  late BookSource _source;

  int get _activeFilterCount {
    switch (_mode) {
      case SearchMode.fulltext:
        // The full-text request DOES carry language / extension
        // (`/fulltext/?…&languages[]=…&extensions[]=…`, verified
        // end-to-end: search_screen → FullTextSearchParams →
        // ZLibraryFullText.searchFullText), and the sheet shows both
        // sections in this mode — so the badge counts them, same as
        // the general branch. Only article mode hides those filters.
        return (_selectedLanguage != 'all' ? 1 : 0) +
            (_selectedOrder != 'popular' ? 1 : 0) +
            (_selectedExtension != 'all' ? 1 : 0) +
            (_fullTextMatchType != 'words' ? 1 : 0) +
            (_fullTextExact ? 1 : 0);
      case SearchMode.article:
        // Article search sends only the query and sort (v1) — the
        // sheet hides the language / extension sections so the UI
        // never promises a filter the request does not carry.
        return _selectedOrder != 'default' ? 1 : 0;
      case SearchMode.general:
        return (_selectedLanguage != 'all' ? 1 : 0) +
            (_selectedOrder != 'default' ? 1 : 0) +
            (_selectedExtension != 'all' ? 1 : 0);
    }
  }

  @override
  void initState() {
    super.initState();
    _source = widget.initialSource ?? BookSource.zlibrary;
    final savedSearches = HiveService.settingsBox.get(_recentSearchesKey);
    if (savedSearches is List) {
      final seen = <String>{};
      _recentSearches = savedSearches
          .whereType<String>()
          .map((keyword) => keyword.trim())
          .where(
            (keyword) => keyword.isNotEmpty && seen.add(keyword.toLowerCase()),
          )
          .take(_recentSearchesLimit)
          .toList();
    }
    _searchController.addListener(_onQueryChanged);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    _searchController.removeListener(_onQueryChanged);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Suggestions ──────────────────────────────────────────────

  void _onQueryChanged() {
    final text = _searchController.text.trim();
    final isEmpty = text.isEmpty;
    final showSuggestions = !isEmpty && text != _lastSubmittedQuery;
    if (isEmpty != _isQueryEmpty || showSuggestions != _showSuggestions) {
      setState(() {
        _isQueryEmpty = isEmpty;
        _showSuggestions = showSuggestions;
      });
    }
    _scheduleSuggestions(text);
  }

  void _scheduleSuggestions(String query) {
    _suggestDebounce?.cancel();
    if (query.isEmpty || query == _lastSubmittedQuery) {
      if (_suggestions.isNotEmpty || _suggestionsLoading) {
        setState(() {
          _suggestions = [];
          _suggestionsLoading = false;
        });
      }
      return;
    }
    _suggestDebounce = Timer(const Duration(milliseconds: 350), () {
      _fetchSuggestions(query);
    });
  }

  Future<void> _fetchSuggestions(String query) async {
    if (!mounted) return;
    if (query == _lastSubmittedQuery) return;
    setState(() => _suggestionsLoading = true);
    final results = await _suggestApi.fetchSuggestions(query);
    if (!mounted) return;
    if (_searchController.text.trim() != query ||
        query == _lastSubmittedQuery) {
      return;
    }
    setState(() {
      _suggestions = results;
      _suggestionsLoading = false;
    });
  }

  // ── Recent searches ──────────────────────────────────────────

  Future<void> _saveRecentSearches(List<String> searches) async {
    setState(() => _recentSearches = searches);
    try {
      await HiveService.settingsBox.put(_recentSearchesKey, searches);
    } catch (error) {
      AppLog.report(
        'Failed to save recent searches: ${error.runtimeType}',
        tag: 'search_screen',
      );
      if (mounted) {
        showAppSnack(context,
              AppLocalizations.of(context)!.searchHistorySaveFailed,
            );
      }
    }
  }

  void _rememberSearch(String query) {
    final normalized = query.toLowerCase();
    final searches = [
      query,
      ..._recentSearches.where((item) => item.toLowerCase() != normalized),
    ].take(_recentSearchesLimit).toList();
    unawaited(_saveRecentSearches(searches));
  }

  void _searchAgain(String keyword) {
    _searchController.text = keyword;
    _searchController.selection = TextSelection.collapsed(
      offset: keyword.length,
    );
    FocusScope.of(context).unfocus();
    _performSearch();
  }

  void _removeRecentSearch(String keyword) {
    unawaited(
      _saveRecentSearches(
        _recentSearches.where((item) => item != keyword).toList(),
      ),
    );
  }

  void _clearRecentSearches() {
    unawaited(_saveRecentSearches([]));
  }

  /// Fill the field with a suggestion without searching (the trailing
  /// arrow in the suggestions view).
  void _insertSuggestion(String suggestion) {
    _searchController.text = suggestion;
    _searchController.selection = TextSelection.collapsed(
      offset: suggestion.length,
    );
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _lastSubmittedQuery = '');
    ref.read(searchProvider.notifier).reset();
    ref.read(fulltextSearchProvider.notifier).reset();
    ref.read(articleSearchProvider.notifier).reset();
    ref.read(externalSearchProvider.notifier).reset();
  }

  // ── Filter handling ──────────────────────────────────────────

  /// A filter change re-runs the current query immediately so the
  /// result set always reflects the visible filter chips.
  void _applyFilterChange() {
    setState(() {});
    final query = _searchController.text.trim();
    if (query.isNotEmpty && query == _lastSubmittedQuery) {
      _performSearch();
    }
  }

  void _resetLanguageFilter() {
    _selectedLanguage = 'all';
    _applyFilterChange();
  }

  void _resetOrderFilter() {
    _selectedOrder = _mode == SearchMode.fulltext ? 'popular' : 'default';
    _applyFilterChange();
  }

  void _resetExtensionFilter() {
    _selectedExtension = 'all';
    _applyFilterChange();
  }

  /// The filter button in the search bar: opens the sheet with the
  /// current locale's display names (same maps the chips mirror).
  /// Article mode passes empty language / extension maps — their
  /// sections hide (the request carries none of those filters).
  void _openFilterSheetForCurrentLocale() {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).languageCode;
    final isArticle = _mode == SearchMode.article;
    unawaited(
      _openFilterSheet(
        l10n,
        isArticle
            ? const <String, String>{}
            : getLanguageDisplayNames(locale),
        _mode == SearchMode.fulltext
            ? getFulltextOrderDisplayNames(locale)
            : getOrderDisplayNames(locale),
        isArticle
            ? const <String, String>{}
            : getExtensionDisplayNames(locale),
      ),
    );
  }

  Future<void> _openFilterSheet(
    AppLocalizations l10n,
    Map<String, String> languageNames,
    Map<String, String> orderNames,
    Map<String, String> extensionNames,
  ) async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final cs = Theme.of(context).colorScheme;
            Widget section(
              String? title,
              Map<String, String> names,
              String selected,
              ValueChanged<String> onSelected,
            ) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) ...[
                    Text(
                      title,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in names.entries)
                        ChoiceChip(
                          label: Text(entry.value),
                          selected: selected == entry.key,
                          showCheckmark: false,
                          selectedColor: cs.primaryContainer,
                          side: BorderSide(
                            color: selected == entry.key
                                ? cs.primary
                                : cs.outlineVariant,
                          ),
                          labelStyle: TextStyle(
                            color: selected == entry.key
                                ? cs.onPrimaryContainer
                                : cs.onSurfaceVariant,
                            fontWeight: selected == entry.key
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                          onSelected: (_) {
                            onSelected(entry.key);
                            setSheetState(() {});
                            _applyFilterChange();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              );
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                20 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_mode == SearchMode.fulltext) ...[
                      section(
                        l10n.matchMode,
                        {
                          'phrase': l10n.matchByPhrase,
                          'words': l10n.matchByWords,
                        },
                        _fullTextMatchType,
                        (v) => _fullTextMatchType = v,
                      ),
                      SwitchListTile(
                        title: Text(l10n.exactMatch),
                        value: _fullTextExact,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (value) {
                          setSheetState(() => _fullTextExact = value);
                          _applyFilterChange();
                        },
                      ),
                      const SizedBox(height: 20),
                    ],
                    // Article mode sends only the query and sort, so
                    // its language / extension sections stay hidden
                    // (empty maps from the caller).
                    if (languageNames.isNotEmpty)
                      section(
                        l10n.language,
                        languageNames,
                        _selectedLanguage,
                        (v) => _selectedLanguage = v,
                      ),
                    section(
                      l10n.sort,
                      orderNames,
                      _selectedOrder,
                      (v) => _selectedOrder = v,
                    ),
                    if (extensionNames.isNotEmpty)
                      section(
                        null,
                        extensionNames,
                        _selectedExtension,
                        (v) => _selectedExtension = v,
                      ),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            setSheetState(() {
                              _selectedLanguage = 'all';
                              _selectedOrder =
                                  _mode == SearchMode.fulltext
                                      ? 'popular'
                                      : 'default';
                              _selectedExtension = 'all';
                              _fullTextMatchType = 'words';
                              _fullTextExact = false;
                            });
                            _applyFilterChange();
                          },
                          icon: const Icon(Icons.restart_alt_rounded, size: 18),
                          label: Text(l10n.searchHistoryClear),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(l10n.close),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Search execution ─────────────────────────────────────────

  void _performSearch() {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _lastSubmittedQuery = query;
      _suggestions = [];
      _suggestionsLoading = false;
      _showSuggestions = false;
    });
    if (_runSearch()) _rememberSearch(query);
  }

  bool _runSearch() {
    if (ref.read(updateProvider).isBlocked) {
      unawaited(showUpdateDialog(context));
      return false;
    }

    final query = _searchController.text.trim();
    if (_source != BookSource.zlibrary) {
      ref.read(externalSearchProvider.notifier).search(query, _source);
      return true;
    }

    if (_mode == SearchMode.fulltext) {
      ref.read(fulltextSearchProvider.notifier).search(
        FullTextSearchParams(
          query: query,
          type: _fullTextMatchType,
          exact: _fullTextExact,
          languages: searchLanguages[_selectedLanguage] != null
              ? [searchLanguages[_selectedLanguage]!]
              : null,
          extensions: searchExtensions[_selectedExtension] != null
              ? [searchExtensions[_selectedExtension]!]
              : null,
          order: _selectedOrder,
        ),
      );
      return true;
    }

    if (_mode == SearchMode.article) {
      ref.read(articleSearchProvider.notifier).search(
        ArticleSearchParams(
          query: query,
          order: searchOrders[_selectedOrder],
        ),
      );
      return true;
    }

    ref
        .read(searchProvider.notifier)
        .search(
          SearchParams(
            query: query,
            languages: searchLanguages[_selectedLanguage] != null
                ? [searchLanguages[_selectedLanguage]!]
                : null,
            extensions: searchExtensions[_selectedExtension] != null
                ? [searchExtensions[_selectedExtension]!]
                : null,
            order: searchOrders[_selectedOrder],
          ),
        );
    return true;
  }

  void _switchSource(BookSource source) {
    if (source == _source) return;
    setState(() {
      _source = source;
      _suggestions = [];
      _suggestionsLoading = false;
      _showSuggestions = false;
      _lastSubmittedQuery = '';
    });
    ref.read(searchProvider.notifier).reset();
    ref.read(fulltextSearchProvider.notifier).reset();
    ref.read(articleSearchProvider.notifier).reset();
    ref.read(externalSearchProvider.notifier).reset();
    if (_searchController.text.trim().isNotEmpty) _performSearch();
  }

  /// Switch between the z站 search modes (通用 / 文章 / 全文检索). The
  /// sort selection resets to the new mode's default ('popular' for
  /// full-text, 'default' for general and article) so a sort value
  /// from one mode can never leak into the other endpoint's request.
  void _switchMode(SearchMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _selectedOrder = mode == SearchMode.fulltext ? 'popular' : 'default';
      _suggestions = [];
      _suggestionsLoading = false;
      _showSuggestions = false;
      _lastSubmittedQuery = '';
    });
    ref.read(searchProvider.notifier).reset();
    ref.read(fulltextSearchProvider.notifier).reset();
    ref.read(articleSearchProvider.notifier).reset();
    if (_searchController.text.trim().isNotEmpty) _performSearch();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (_source != BookSource.zlibrary) {
        ref.read(externalSearchProvider.notifier).loadMore();
      } else if (_mode == SearchMode.fulltext) {
        ref.read(fulltextSearchProvider.notifier).loadMore();
      } else if (_mode == SearchMode.article) {
        ref.read(articleSearchProvider.notifier).loadMore();
      } else {
        ref.read(searchProvider.notifier).loadMore();
      }
    }
  }

  void _openBook(DisplayBook book) {
    AppRoutes.openBookDetailForDisplayBook(context, book);
  }

  void _openFullTextHit(FullTextHit hit) {
    AppRoutes.openBookDetailForDisplayBook(
      context,
      hit.book.toDisplay(),
      unavailableReason: hit.unavailableReason,
    );
  }

  /// Opens one article's site detail page in the reader WebView —
  /// the same session-installed page the online reader uses. Articles
  /// have no eapi detail flow (those endpoints are book-only), so the
  /// site's own page (which carries the download button) is the v1
  /// interaction. The URL host is the API line's own domain — the
  /// same host the session was already issued for — so the session
  /// rides along whenever the user is signed in. Removed articles
  /// still open (site behaviour: the page stays reachable).
  void _openArticle(Article article) {
    final url = article.url;
    if (url == null || url.isEmpty) return;
    final user = ref.read(authProvider).user;
    AppRoutes.openReader(
      context,
      ReaderArgs(
        url: url,
        title: article.title,
        remixUserId: user?.id,
        remixUserKey: user?.remixUserkey,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).languageCode;
    final languageNames = getLanguageDisplayNames(locale);
    final orderNames = _mode == SearchMode.fulltext
        ? getFulltextOrderDisplayNames(locale)
        : getOrderDisplayNames(locale);
    final extensionNames = getExtensionDisplayNames(locale);
    final isExternal = _source != BookSource.zlibrary;

    final searchState = ref.watch(searchProvider);
    final externalState = ref.watch(externalSearchProvider);
    final fulltextState = ref.watch(fulltextSearchProvider);
    final articleState = ref.watch(articleSearchProvider);
    final isFullTextMode = _mode == SearchMode.fulltext && !isExternal;
    final isArticleMode = _mode == SearchMode.article && !isExternal;
    final books = isExternal
        ? externalState.books
        : searchState.books.map((book) => book.toDisplay()).toList();
    final resultCount = isFullTextMode
        ? fulltextState.hits.length
        : isArticleMode
        ? articleState.articles.length
        : books.length;
    final hasSearched = isExternal
        ? externalState.hasSearched
        : isFullTextMode
        ? fulltextState.hasSearched
        : isArticleMode
        ? articleState.hasSearched
        : searchState.hasSearched;
    final isLoading = isExternal
        ? externalState.isLoading
        : isFullTextMode
        ? fulltextState.isLoading
        : isArticleMode
        ? articleState.isLoading
        : searchState.isLoading;
    final isLoadingMore = isExternal
        ? externalState.isLoadingMore
        : isFullTextMode
        ? fulltextState.isLoadingMore
        : isArticleMode
        ? articleState.isLoadingMore
        : searchState.isLoadingMore;
    final loginRequired = isFullTextMode && fulltextState.loginRequired;
    final error = isExternal
        ? externalState.error
        : isFullTextMode
        ? (fulltextState.error == fulltextTokenUnavailable
              ? l10n.fullTextUnavailable
              : fulltextState.error)
        : isArticleMode
        ? articleState.error
        : searchState.error;
    final currentPage = isExternal
        ? externalState.currentPage
        : isFullTextMode
        ? fulltextState.currentPage
        : isArticleMode
        ? articleState.currentPage
        : searchState.currentPage;
    final totalPagesText = isExternal
        ? (externalState.hasMore ? '…' : '${externalState.currentPage}')
        : isFullTextMode
        ? '${fulltextState.totalPages}'
        : isArticleMode
        ? '${articleState.totalPages}'
        : '${searchState.totalPages}';

    return Scaffold(
      appBar: GradientAppBar(title: l10n.searchBooks),
      body: Column(
        children: [
          SearchBarField(
            l10n: l10n,
            controller: _searchController,
            isExternal: isExternal,
            activeFilterCount: _activeFilterCount,
            isQueryEmpty: _isQueryEmpty,
            hintText: _mode == SearchMode.fulltext
                ? l10n.fullTextSearchHint
                : null,
            onSubmitted: _performSearch,
            onFilterTap: _openFilterSheetForCurrentLocale,
            onClear: _clearSearch,
          ),
          SearchSourceSelector(
            l10n: l10n,
            selected: _source,
            onSwitch: _switchSource,
          ),
          if (!isExternal)
            SearchModeSelector(
              l10n: l10n,
              mode: _mode,
              onSwitch: _switchMode,
            ),
          if (!isExternal && _activeFilterCount > 0)
            SearchActiveFilterChips(
              l10n: l10n,
              languageNames: languageNames,
              orderNames: orderNames,
              extensionNames: extensionNames,
              selectedLanguage: _selectedLanguage,
              selectedOrder: _selectedOrder,
              selectedExtension: _selectedExtension,
              onResetLanguage: _resetLanguageFilter,
              onResetOrder: _resetOrderFilter,
              onResetExtension: _resetExtensionFilter,
            ),
          Expanded(
            child: _isQueryEmpty
                ? SearchEmptyQueryView(
                    l10n: l10n,
                    recentSearches: _recentSearches,
                    onSearch: _searchAgain,
                    onRemoveSearch: _removeRecentSearch,
                    onClearHistory: _clearRecentSearches,
                    onBrowseCategories: () =>
                        AppRoutes.openCategories(context),
                  )
                : _showSuggestions
                ? SearchSuggestionsView(
                    l10n: l10n,
                    suggestions: _suggestions,
                    isLoading: _suggestionsLoading,
                    query: _searchController.text.trim(),
                    onSearch: _searchAgain,
                    onInsert: _insertSuggestion,
                  )
                : !hasSearched
                ? EmptyState(
                    icon: Icons.search_rounded,
                    title: l10n.startSearching,
                    message: l10n.enterSearchHint,
                  )
                : isLoading
                ? const SearchSkeletonGrid()
                : loginRequired
                ? EmptyState(
                    icon: Icons.login_rounded,
                    title: l10n.fullTextLoginRequired,
                    action: FilledButton(
                      onPressed: () => AppRoutes.openLogin(context),
                      child: Text(l10n.login),
                    ),
                  )
                : error != null && resultCount == 0
                ? EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: l10n.searchFailed,
                    message: error,
                    action: FilledButton(
                      onPressed: _performSearch,
                      child: Text(l10n.searchRetry),
                    ),
                  )
                : resultCount == 0
                ? EmptyState(
                    icon: Icons.search_off_rounded,
                    title: l10n.noResults,
                    message: l10n.searchNoResultsSwitch,
                  )
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                l10n.searchResultsCount(resultCount),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onPrimaryContainer,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l10n.searchPageProgress(currentPage, totalPagesText),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ),
                            // 文章/全文模式没有网格卡片，视图切换只
                            // 对通用搜索的 DisplayBook 网格有意义。
                            if (!isFullTextMode && !isArticleMode)
                              IconButton(
                                icon: Icon(
                                  _isListView
                                      ? Icons.grid_view_rounded
                                      : Icons.view_list_rounded,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 22,
                                ),
                                tooltip: _isListView
                                    ? l10n.gridView
                                    : l10n.listView,
                                onPressed: () {
                                  setState(() => _isListView = !_isListView);
                                },
                              ),
                          ],
                        ),
                      ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(l10n.searchMoreFailed),
                              ),
                              TextButton(
                                onPressed: () {
                                  if (isExternal) {
                                    ref
                                        .read(externalSearchProvider.notifier)
                                        .loadMore();
                                  } else if (isFullTextMode) {
                                    ref
                                        .read(fulltextSearchProvider.notifier)
                                        .loadMore();
                                  } else if (isArticleMode) {
                                    ref
                                        .read(articleSearchProvider.notifier)
                                        .loadMore();
                                  } else {
                                    ref
                                        .read(searchProvider.notifier)
                                        .loadMore();
                                  }
                                },
                                child: Text(l10n.searchRetry),
                              ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: isFullTextMode
                            ? ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  16,
                                ),
                                itemCount: fulltextState.hits.length +
                                    (isLoadingMore ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index >= fulltextState.hits.length) {
                                    return const LoadingWidget.more();
                                  }
                                  final hit = fulltextState.hits[index];
                                  return FullTextHitTile(
                                    hit: hit,
                                    l10n: l10n,
                                    onTap: () => _openFullTextHit(hit),
                                  );
                                },
                              )
                            : isArticleMode
                            ? ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  16,
                                ),
                                itemCount: articleState.articles.length +
                                    (isLoadingMore ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index >=
                                      articleState.articles.length) {
                                    return const LoadingWidget.more();
                                  }
                                  final article =
                                      articleState.articles[index];
                                  return ArticleTile(
                                    article: article,
                                    l10n: l10n,
                                    onTap: () => _openArticle(article),
                                  );
                                },
                              )
                            : _isListView
                            ? ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  16,
                                ),
                                itemCount:
                                    books.length + (isLoadingMore ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index >= books.length) {
                                    return const LoadingWidget.more();
                                  }
                                  final book = books[index];
                                  return BookListTile(
                                    book: book,
                                    showCover: true,
                                    onTap: () => _openBook(book),
                                  );
                                },
                              )
                            : GridView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  16,
                                ),
                                gridDelegate:
                                    const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 220,
                                      childAspectRatio: 0.60,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                    ),
                                itemCount:
                                    books.length + (isLoadingMore ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index >= books.length) {
                                    return const LoadingWidget.more();
                                  }
                                  final book = books[index];
                                  return BookCard(
                                    book: book,
                                    searchResult: true,
                                    // 搜索结果同屏同 id 重复极罕见
                                    // （不同 edition id 不同），
                                    // 可安全开 Hero。
                                    heroEnabled: true,
                                    onTap: () => _openBook(book),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
