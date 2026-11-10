import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/books_provider.dart';
import '../../providers/trending_provider.dart';
import '../../widgets/book_card.dart';
import '../../widgets/book_list_tile.dart';
import '../../widgets/cover_placeholder.dart';
import 'widgets/trending_section.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/gradient_app_bar.dart';
import '../../widgets/update_dialog.dart';
import '../../models/display_book.dart';
import '../../routes/app_routes.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../constants/search_filters.dart';
import '../../services/google_suggest_api.dart';
import '../../services/open_library.dart';
import '../../providers/update_provider.dart';
import '../../services/hive_service.dart';

import '../../utils/app_snack.dart';
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

  // ── Filters (applied immediately, edited in a bottom sheet) ──
  String _selectedLanguage = 'all';
  String _selectedOrder = 'default';
  String _selectedExtension = 'all';

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

  int get _activeFilterCount =>
      (_selectedLanguage != 'all' ? 1 : 0) +
      (_selectedOrder != 'default' ? 1 : 0) +
      (_selectedExtension != 'all' ? 1 : 0);

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
      debugPrint('Failed to save recent searches: ${error.runtimeType}');
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

  void _clearSearch() {
    _searchController.clear();
    setState(() => _lastSubmittedQuery = '');
    ref.read(searchProvider.notifier).reset();
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
                              _selectedOrder = 'default';
                              _selectedExtension = 'all';
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
      showUpdateDialog(context);
      return false;
    }

    final query = _searchController.text.trim();
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
      _suggestions = [];
      _suggestionsLoading = false;
      _showSuggestions = false;
      _lastSubmittedQuery = '';
    });
    ref.read(searchProvider.notifier).reset();
    ref.read(externalSearchProvider.notifier).reset();
    if (_searchController.text.trim().isNotEmpty) _performSearch();
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
    Navigator.of(context).pushNamed(
      AppRoutes.bookDetail,
      arguments: book.isZLibrary ? book.asZLibBook : book,
    );
  }

  // ── UI builders ──────────────────────────────────────────────

  /// Pill-shaped search bar; filter button opens the bottom sheet and
  /// carries a badge with the number of active filters.
  Widget _buildSearchBar(
    AppLocalizations l10n,
    bool isExternal,
  ) {
    final cs = Theme.of(context).colorScheme;
    const radius = BorderRadius.all(Radius.circular(28));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _performSearch(),
        decoration: InputDecoration(
          hintText: l10n.searchForBooks,
          hintStyle: TextStyle(color: cs.onSurfaceVariant),
          prefixIcon: Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isExternal)
                Badge(
                  isLabelVisible: _activeFilterCount > 0,
                  label: Text('$_activeFilterCount'),
                  child: IconButton(
                    icon: Icon(
                      Icons.tune_rounded,
                      color: _activeFilterCount > 0
                          ? cs.primary
                          : cs.onSurfaceVariant,
                    ),
                    onPressed: () => _openFilterSheet(
                      l10n,
                      getLanguageDisplayNames(
                        Localizations.localeOf(context).languageCode,
                      ),
                      getOrderDisplayNames(
                        Localizations.localeOf(context).languageCode,
                      ),
                      getExtensionDisplayNames(
                        Localizations.localeOf(context).languageCode,
                      ),
                    ),
                  ),
                ),
              if (!_isQueryEmpty)
                IconButton(
                  icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                  onPressed: _clearSearch,
                ),
            ],
          ),
          filled: true,
          fillColor: cs.surfaceContainerHighest,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 14,
          ),
          border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
          enabledBorder:
              OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(color: cs.primary, width: 1.4),
          ),
        ),
      ),
    );
  }

  /// Sliding-highlight segmented control for the search source.
  Widget _buildSourceSelector(AppLocalizations l10n) {
    final items = <BookSource>[
      BookSource.zlibrary,
      BookSource.annasArchive,
      BookSource.libgen,
    ];
    final icons = <BookSource, IconData>{
      BookSource.zlibrary: Icons.auto_stories_rounded,
      BookSource.annasArchive: Icons.public_rounded,
      BookSource.libgen: Icons.menu_book_rounded,
    };
    final labels = <BookSource, String>{
      BookSource.zlibrary: l10n.sourceZlibrary,
      BookSource.annasArchive: l10n.sourceAnnasArchive,
      BookSource.libgen: l10n.sourceLibgen,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            for (final source in items)
              Expanded(
                child: _SourceSegment(
                  icon: icons[source]!,
                  label: labels[source]!,
                  selected: _source == source,
                  onTap: () => _switchSource(source),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Compact removable chips mirroring the filters applied in the
  /// sheet — deleting one resets it and re-searches.
  Widget _buildActiveFilterChips(
    AppLocalizations l10n,
    Map<String, String> languageNames,
    Map<String, String> orderNames,
    Map<String, String> extensionNames,
  ) {
    final cs = Theme.of(context).colorScheme;
    final chips = <Widget>[];

    void addChip(String label, VoidCallback onDeleted) {
      chips.add(
        InputChip(
          label: Text(label),
          onDeleted: onDeleted,
          deleteIconColor: cs.onPrimaryContainer,
          backgroundColor: cs.primaryContainer,
          side: BorderSide.none,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          labelStyle: TextStyle(
            color: cs.onPrimaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    if (_selectedLanguage != 'all') {
      addChip(
        '${l10n.language}: ${languageNames[_selectedLanguage]}',
        () {
          _selectedLanguage = 'all';
          _applyFilterChange();
        },
      );
    }
    if (_selectedOrder != 'default') {
      addChip(
        '${l10n.sort}: ${orderNames[_selectedOrder]}',
        () {
          _selectedOrder = 'default';
          _applyFilterChange();
        },
      );
    }
    if (_selectedExtension != 'all') {
      addChip(
        '${extensionNames[_selectedExtension]}',
        () {
          _selectedExtension = 'all';
          _applyFilterChange();
        },
      );
    }

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) => chips[index],
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    Widget? trailing,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildEmptyQueryView(AppLocalizations l10n) {
    final trendingAsync = ref.watch(trendingBooksProvider);
    final trendingBooks = (trendingAsync.valueOrNull ??
            const <TrendingBookData>[])
        .where((book) => book.title?.trim().isNotEmpty ?? false)
        .toList();
    if (_recentSearches.isEmpty && trendingBooks.isEmpty) {
      if (trendingAsync.isLoading) {
        return const LoadingWidget.page(padding: EdgeInsets.all(24));
      }
      return EmptyState(
        icon: Icons.search_rounded,
        title: l10n.startSearching,
        message: l10n.enterSearchHint,
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (_recentSearches.isNotEmpty) _buildRecentSearchesSection(l10n),
        if (trendingBooks.isNotEmpty) ...[
          if (_recentSearches.isNotEmpty) const SizedBox(height: 28),
          SearchTrendingSection(
            l10n: l10n,
            books: trendingBooks,
            onSearch: _searchAgain,
          ),
        ],
      ],
    );
  }

  Widget _buildRecentSearchesSection(AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.history_rounded,
          title: l10n.searchHistoryTitle,
          trailing: TextButton.icon(
            onPressed: () => unawaited(_saveRecentSearches([])),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: Text(l10n.searchHistoryClear),
          ),
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
                deleteButtonTooltipMessage: l10n.searchHistoryRemove,
                backgroundColor: cs.surfaceContainerLow,
                side: BorderSide(color: cs.outlineVariant),
              ),
          ],
        ),
      ],
    );
  }

  /// Suggestions for the text being typed; the matching prefix is
  /// highlighted, and the trailing arrow inserts without searching.
  Widget _buildSuggestionsView(AppLocalizations l10n) {
    if (_suggestionsLoading && _suggestions.isEmpty) {
      return const LoadingWidget.page(padding: EdgeInsets.all(24));
    }
    if (_suggestions.isEmpty) {
      return EmptyState(
        icon: Icons.search_rounded,
        title: l10n.startSearching,
        message: l10n.enterSearchHint,
      );
    }
    final query = _searchController.text.trim();
    final cs = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
      itemCount: _suggestions.length,
      itemBuilder: (context, index) {
        final suggestion = _suggestions[index];
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _searchAgain(suggestion),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _highlightedText(suggestion, query),
                ),
                IconButton(
                  icon: Icon(
                    Icons.north_west_rounded,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                  onPressed: () {
                    _searchController.text = suggestion;
                    _searchController.selection = TextSelection.collapsed(
                      offset: suggestion.length,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _highlightedText(String suggestion, String query) {
    final style = Theme.of(context).textTheme.bodyLarge;
    if (query.isEmpty) {
      return Text(suggestion, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    final idx = suggestion.toLowerCase().indexOf(query.toLowerCase());
    if (idx < 0) {
      return Text(suggestion, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    final cs = Theme.of(context).colorScheme;
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: suggestion.substring(0, idx)),
          TextSpan(
            text: suggestion.substring(idx, idx + query.length),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: cs.primary,
            ),
          ),
          TextSpan(text: suggestion.substring(idx + query.length)),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildSkeletonGrid() {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        childAspectRatio: 0.60,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: 8,
      itemBuilder: (_, __) {
        // 骨架用已有的 CoverPlaceholder.shimmer（1500ms 渐变扫过），
        // 不再用静态灰块；布局、数量、尺寸与原来一致。
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CoverPlaceholder.shimmer(),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        height: 12,
                        width: double.infinity,
                        child: CoverPlaceholder.shimmer(),
                      ),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: SizedBox(
                        height: 10,
                        width: 80,
                        child: CoverPlaceholder.shimmer(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).languageCode;
    final languageNames = getLanguageDisplayNames(locale);
    final orderNames = getOrderDisplayNames(locale);
    final extensionNames = getExtensionDisplayNames(locale);
    final isExternal = _source != BookSource.zlibrary;

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
    final totalPagesText = isExternal
        ? (externalState.hasMore ? '…' : '${externalState.currentPage}')
        : '${searchState.totalPages}';

    return Scaffold(
      appBar: GradientAppBar(title: l10n.searchBooks),
      body: Column(
        children: [
          _buildSearchBar(l10n, isExternal),
          _buildSourceSelector(l10n),
          if (!isExternal && _activeFilterCount > 0)
            _buildActiveFilterChips(l10n, languageNames, orderNames, extensionNames),
          Expanded(
            child: _isQueryEmpty
                ? _buildEmptyQueryView(l10n)
                : _showSuggestions
                ? _buildSuggestionsView(l10n)
                : !hasSearched
                ? EmptyState(
                    icon: Icons.search_rounded,
                    title: l10n.startSearching,
                    message: l10n.enterSearchHint,
                  )
                : isLoading
                ? _buildSkeletonGrid()
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

/// One segment of the sliding-highlight source selector.
class _SourceSegment extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SourceSegment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: selected
                          ? cs.onPrimaryContainer
                          : cs.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}