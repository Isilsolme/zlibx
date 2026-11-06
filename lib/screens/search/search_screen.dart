import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import '../../providers/books_provider.dart';
import '../../providers/trending_provider.dart';
import '../../widgets/book_card.dart';
import '../../widgets/book_list_tile.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/gradient_app_bar.dart';
import '../../widgets/update_dialog.dart';
import '../../models/display_book.dart';
import '../../routes/app_routes.dart';
import '../../l10n/app_localizations.dart';
import '../../constants/search_filters.dart';
import '../../services/google_suggest_api.dart';
import '../../services/open_library.dart';
import '../../services/update_service.dart';
import '../../services/hive_service.dart';

const _recentSearchesKey = 'recent_search_keywords';
const _recentSearchesLimit = 12;

class SearchScreen extends ConsumerStatefulWidget {
  final BookSource? initialSource;

  const SearchScreen({super.key, this.initialSource});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  bool _showFilters = false;
  String _selectedLanguage = 'all';
  String _selectedOrder = 'default';
  String _selectedExtension = 'all';
  bool _isListView = false;
  bool _isQueryEmpty = true;
  List<String> _recentSearches = [];
  // Search suggestions (ported from OpenlibExtended's GoogleSuggestApi):
  // debounced while typing, shown until a query is submitted. A failed
  // fetch stays silent — the list is simply empty.
  final _suggestApi = GoogleSuggestApi();
  Timer? _suggestDebounce;
  List<String> _suggestions = [];
  bool _suggestionsLoading = false;
  bool _showSuggestions = false;
  String _lastSubmittedQuery = '';
  // Search source: Z-Library by default; the (unused) initialSource route
  // parameter is the entry point for opening the screen on Anna's Archive.
  late BookSource _source;

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
    _suggestDebounce = Timer(const Duration(milliseconds: 400), () {
      _fetchSuggestions(query);
    });
  }

  Future<void> _fetchSuggestions(String query) async {
    if (!mounted) return;
    // The query may have been submitted while the debounce was waiting;
    // never spin the loading flag for it.
    if (query == _lastSubmittedQuery) return;
    setState(() => _suggestionsLoading = true);
    final results = await _suggestApi.fetchSuggestions(query);
    if (!mounted) return;
    // Ignore stale responses: the user may have typed on, cleared the
    // field, or submitted since the request started.
    if (_searchController.text.trim() != query ||
        query == _lastSubmittedQuery) {
      return;
    }
    setState(() {
      _suggestions = results;
      _suggestionsLoading = false;
    });
  }

  Future<void> _saveRecentSearches(List<String> searches) async {
    setState(() => _recentSearches = searches);
    try {
      await HiveService.settingsBox.put(_recentSearchesKey, searches);
    } catch (error) {
      debugPrint('Failed to save recent searches: ${error.runtimeType}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).get('search_history_save_failed'),
            ),
          ),
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

  /// Empty query: recent searches (if any) plus the Open Library
  /// trending feed. The trending section hides itself when the feed
  /// fails or comes back empty; when there is nothing at all to show,
  /// the usual "start searching" empty state is shown instead.
  Widget _buildEmptyQueryView(AppLocalizations l10n) {
    final trendingAsync = ref.watch(trendingBooksProvider);
    final trendingBooks = (trendingAsync.valueOrNull ??
            const <TrendingBookData>[])
        .where((book) => book.title?.trim().isNotEmpty ?? false)
        .toList();
    if (_recentSearches.isEmpty && trendingBooks.isEmpty) {
      if (trendingAsync.isLoading) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ),
        );
      }
      return EmptyState(
        icon: Icons.search,
        title: l10n.get('start_searching'),
        message: l10n.get('enter_search_hint'),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (_recentSearches.isNotEmpty) _buildRecentSearchesSection(l10n),
        if (trendingBooks.isNotEmpty) ...[
          if (_recentSearches.isNotEmpty) const SizedBox(height: 24),
          _buildTrendingSection(l10n, trendingBooks),
        ],
      ],
    );
  }

  Widget _buildRecentSearchesSection(AppLocalizations l10n) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.history_rounded, size: 20, color: colors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.get('search_history_title'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton.icon(
              onPressed: () => unawaited(_saveRecentSearches([])),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: Text(l10n.get('search_history_clear')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final keyword in _recentSearches)
              InputChip(
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(keyword, overflow: TextOverflow.ellipsis),
                ),
                onPressed: () => _searchAgain(keyword),
                onDeleted: () => unawaited(
                  _saveRecentSearches(
                    _recentSearches.where((item) => item != keyword).toList(),
                  ),
                ),
                deleteButtonTooltipMessage: l10n.get('search_history_remove'),
                backgroundColor: colors.surfaceContainerLow,
                side: BorderSide(color: colors.outlineVariant),
              ),
          ],
        ),
      ],
    );
  }

  /// Suggestions for the text being typed. Tapping one searches it.
  Widget _buildSuggestionsView(AppLocalizations l10n) {
    if (_suggestionsLoading && _suggestions.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_suggestions.isEmpty) {
      return EmptyState(
        icon: Icons.search,
        title: l10n.get('start_searching'),
        message: l10n.get('enter_search_hint'),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
      itemCount: _suggestions.length,
      itemBuilder: (context, index) {
        final suggestion = _suggestions[index];
        return ListTile(
          leading: const Icon(Icons.search, size: 20),
          title: Text(
            suggestion,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _searchAgain(suggestion),
        );
      },
    );
  }

  /// Open Library trending (ported from OpenlibExtended): a horizontal
  /// cover strip. Tapping a cover searches its title on the current
  /// source, exactly like upstream's trending page does.
  Widget _buildTrendingSection(
    AppLocalizations l10n,
    List<TrendingBookData> books,
  ) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.local_fire_department_outlined,
              size: 20,
              color: colors.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.get('trending_on_open_library'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: books.length,
            itemBuilder: (context, index) {
              final book = books[index];
              final title = book.title!.trim();
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: InkWell(
                  onTap: () => _searchAgain(title),
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 105,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: book.thumbnail ?? '',
                            height: 145,
                            width: 105,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              height: 145,
                              width: 105,
                              color: colors.surfaceContainerHighest,
                            ),
                            errorWidget: (context, url, error) => Container(
                              height: 145,
                              width: 105,
                              color: colors.surfaceContainerHighest,
                              child: const Icon(Icons.image_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (_source != BookSource.zlibrary) {
        ref.read(externalSearchProvider.notifier).loadMore();
      } else {
        ref.read(searchProvider.notifier).loadMore();
      }
    }
  }

  void _openBook(DisplayBook book) {
    // External results (Anna / LibGen) have no z站 Book: pass the
    // DisplayBook itself; the detail page branches on DisplayBook.source.
    Navigator.of(context).pushNamed(
      AppRoutes.bookDetail,
      arguments: book.isZLibrary ? book.asZLibBook : book,
    );
  }

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
    if (UpdateService.isBlocked) {
      showUpdateDialog(context);
      return false;
    }

    final query = _searchController.text.trim();
    // External sources (Anna's Archive / LibGen): plain text search; the
    // z站 filter panel (language / order / extension) does not apply and
    // is hidden for these sources.
    if (_source != BookSource.zlibrary) {
      ref.read(externalSearchProvider.notifier).search(query, _source);
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
      _showFilters = false;
      _suggestions = [];
      _suggestionsLoading = false;
      _showSuggestions = false;
      _lastSubmittedQuery = '';
    });
    // Stale results must not leak across sources.
    ref.read(searchProvider.notifier).reset();
    ref.read(externalSearchProvider.notifier).reset();
    // Re-run the current query on the new source, if there is one.
    if (_searchController.text.trim().isNotEmpty) _performSearch();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final languageNames = getLanguageDisplayNames(locale);
    final orderNames = getOrderDisplayNames(locale);
    final extensionNames = getExtensionDisplayNames(locale);
    final isExternal = _source != BookSource.zlibrary;
    // Source-dependent search state: z站 (vendor Book) vs external
    // (Anna / LibGen, DisplayBook).
    final searchState = ref.watch(searchProvider);
    final externalState = ref.watch(externalSearchProvider);
    final books = isExternal
        ? externalState.books
        : searchState.books.map((book) => book.toDisplay()).toList();
    final resultCount = books.length;
    final hasSearched =
        isExternal ? externalState.hasSearched : searchState.hasSearched;
    final isLoading =
        isExternal ? externalState.isLoading : searchState.isLoading;
    final isLoadingMore =
        isExternal ? externalState.isLoadingMore : searchState.isLoadingMore;
    final error = isExternal ? externalState.error : searchState.error;
    final currentPage =
        isExternal ? externalState.currentPage : searchState.currentPage;
    // External sources have no total_pages: '…' while more pages may
    // exist, the current page number once the last (empty) page has
    // been reached.
    final totalPagesText = isExternal
        ? (externalState.hasMore ? '…' : '${externalState.currentPage}')
        : '${searchState.totalPages}';

    return Scaffold(
      appBar: GradientAppBar(title: l10n.get('search_books')),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l10n.get('search_for_books'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The filter panel is z站-only; external search is
                    // plain text.
                    if (!isExternal)
                      IconButton(
                        icon: Icon(
                            Icons.tune,
                            color: _showFilters ? Theme.of(context).colorScheme.primary : null,
                          ),
                          onPressed: () {
                            setState(() {
                              _showFilters = !_showFilters;
                            });
                          },
                        ),
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _lastSubmittedQuery = '');
                        ref.read(searchProvider.notifier).reset();
                        ref.read(externalSearchProvider.notifier).reset();
                      },
                    ),
                  ],
                ),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _performSearch(),
            ),
          ),

          // Source Selector (Z-Library / Anna's Archive / LibGen)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<BookSource>(
                segments: [
                  ButtonSegment<BookSource>(
                    value: BookSource.zlibrary,
                    label: Text(l10n.get('source_zlibrary')),
                  ),
                  ButtonSegment<BookSource>(
                    value: BookSource.annasArchive,
                    label: Text(l10n.get('source_annas_archive')),
                  ),
                  ButtonSegment<BookSource>(
                    value: BookSource.libgen,
                    label: Text(l10n.get('source_libgen')),
                  ),
                ],
                selected: {_source},
                onSelectionChanged: (selected) => _switchSource(selected.first),
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ),

          // Filter Panel
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: _buildFilterPanel(
              languageNames,
              orderNames,
              extensionNames,
            ),
            crossFadeState: _showFilters
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),

          // Search Results
          Expanded(
            child: _isQueryEmpty
                ? _buildEmptyQueryView(l10n)
                : _showSuggestions
                ? _buildSuggestionsView(l10n)
                : !hasSearched
                ? EmptyState(
                    icon: Icons.search,
                    title: l10n.get('start_searching'),
                    message: l10n.get('enter_search_hint'),
                  )
                : isLoading
                ? LoadingWidget(message: l10n.get('searching_books'))
                : error != null && resultCount == 0
                ? EmptyState(
                    icon: Icons.error_outline,
                    title: l10n.get('search_failed'),
                    message: error,
                    action: FilledButton(
                      onPressed: _performSearch,
                      child: Text(l10n.get('search_retry')),
                    ),
                  )
                : resultCount == 0
                ? EmptyState(
                    icon: Icons.search_off,
                    title: l10n.get('no_results'),
                    message: l10n.get('search_no_results_switch'),
                  )
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    l10n
                                        .get('search_results_count')
                                        .replaceAll('{count}', '$resultCount'),
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
                              ),
                            ),

                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  l10n
                                      .get('search_page_progress')
                                      .replaceAll(
                                        '{current}',
                                        '$currentPage',
                                      )
                                      .replaceAll(
                                        '{total}',
                                        totalPagesText,
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ),
                            
                            IconButton(
                                icon: Icon(
                                  _isListView
                                      ? Icons.grid_view_rounded
                                      : Icons.view_list_rounded,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 22,
                                ),
                                tooltip: _isListView
                                    ? l10n.get('grid_view')
                                    : l10n.get('list_view'),
                                onPressed: () {
                                  setState(() {
                                    _isListView = !_isListView;
                                  });
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
                                child: Text(l10n.get('search_more_failed')),
                              ),
                              TextButton(
                                onPressed: () {
                                  if (isExternal) {
                                    ref
                                        .read(externalSearchProvider.notifier)
                                        .loadMore();
                                  } else {
                                    ref
                                        .read(searchProvider.notifier)
                                        .loadMore();
                                  }
                                },
                                child: Text(l10n.get('search_retry')),
                              ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: _isListView
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
                                    return const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(16),
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
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
                                    return const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(16),
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  }

                                  final book = books[index];
                                  return BookCard(
                                    book: book,
                                    searchResult: true,
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

  Widget _buildFilterPanel(
    Map<String, String> languageNames,
    Map<String, String> orderNames,
    Map<String, String> extensionNames,
  ) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = Localizations.localeOf(context).languageCode;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildDropdown2(
                  hint: l10n.get('language'),
                  value: _selectedLanguage,
                  items: languageNames.entries
                      .map(
                        (e) => DropdownMenuItem<String>(
                          value: e.key,
                          child: Text(
                            e.value,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedLanguage = value);
                    }
                  },
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDropdown2(
                  hint: locale.startsWith('zh') ? '排序' : 'Sort',
                  value: _selectedOrder,
                  items: orderNames.entries
                      .map(
                        (e) => DropdownMenuItem<String>(
                          value: e.key,
                          child: Text(
                            e.value,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedOrder = value);
                    }
                  },
                  isDark: isDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: extensionNames.entries
                  .map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(entry.value),
                        selected: _selectedExtension == entry.key,
                        selectedColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                        labelStyle: TextStyle(
                          color: _selectedExtension == entry.key
                              ? Theme.of(context).colorScheme.primary
                              : null,
                          fontWeight: _selectedExtension == entry.key
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _selectedExtension = entry.key);
                          }
                        },
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown2({
    required String hint,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
    required bool isDark,
  }) {
    return DropdownButtonHideUnderline(
      child: DropdownButton2<String>(
        isExpanded: true,
        hint: Text(
          hint,
          style: TextStyle(fontSize: 14, color: Theme.of(context).hintColor),
        ),
        items: items,
        value: value,
        onChanged: onChanged,
        buttonStyleData: ButtonStyleData(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
            ),
            color: isDark ? Colors.grey[850] : Colors.white,
          ),
        ),
        iconStyleData: IconStyleData(
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          iconSize: 20,
          iconEnabledColor: Theme.of(context).colorScheme.primary,
        ),
        dropdownStyleData: DropdownStyleData(
          maxHeight: 300,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: isDark ? Colors.grey[900] : Colors.white,
          ),
          scrollbarTheme: ScrollbarThemeData(
            radius: const Radius.circular(40),
            thickness: WidgetStateProperty.all(6),
            thumbVisibility: WidgetStateProperty.all(true),
          ),
        ),
        menuItemStyleData: const MenuItemStyleData(
          height: 40,
          padding: EdgeInsets.symmetric(horizontal: 14),
        ),
      ),
    );
  }
}
