import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';
import 'package:open_filex/open_filex.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../models/unified_shelf_item.dart';
import '../../providers/books_provider.dart';
import '../../providers/download_provider.dart';
import '../../providers/shelf_categories_provider.dart';
import '../../providers/shelf_provider.dart';
import '../../screens/book_detail/book_detail_screen.dart';
import '../../screens/search/search_screen.dart';
import '../../services/media_store.dart';
import 'widgets/shelf_book_item.dart';
import 'widgets/shelf_chip.dart';
import '../../widgets/loading_widget.dart';

import '../../utils/app_snack.dart';
enum _ShelfSort { defaultOrder, title, author }

class _CategoryCommand {
  const _CategoryCommand(this.action, [this.category]);

  final String action;
  final ShelfCategory? category;
}

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  static const _uncategorized = '__uncategorized__';

  final _searchController = TextEditingController();
  bool _isListView = false;
  bool _isSelectMode = false;
  final Set<int> _selectedBookIds = {};
  String? _selectedCategoryId;
  _ShelfSort _sort = _ShelfSort.defaultOrder;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final shelf = ref.watch(unifiedShelfProvider);
    final library = ref.watch(savedBooksProvider);
    final categories = ref.watch(shelfCategoriesProvider);
    final hasSourceError = _sourceError(library);

    final allItems = shelf.valueOrNull ?? <UnifiedShelfItem>[];
    final visible = _filteredItems(allItems, categories);
    // Index built once per build so every item is an O(1) lookup
    // instead of a linear scan over all categories. Download state is
    // deliberately not read here: each tile watches
    // downloadTaskProvider for its own book id, so one progress tick
    // rebuilds only that tile instead of the whole shelf.
    final categoryNameById = <String, String>{
      for (final category in categories.categories)
        category.id: category.name,
    };
    // Only the select-mode app bar needs the visible library ids.
    final selectedVisible = _isSelectMode
        ? visible
              .where((item) => item.source == ShelfSource.library)
              .map((item) => int.tryParse(item.rawBookId))
              .whereType<int>()
              .toSet()
        : const <int>{};

    return Scaffold(
      body: shelf is AsyncLoading && allItems.isEmpty
          ? LoadingWidget.page(message: l.loadingFavorites)
          : RefreshIndicator(
              onRefresh: () async {
                await ref
                    .read(savedBooksProvider.notifier)
                    .loadSavedBooks();
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  _appBar(l, selectedVisible),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                      child: Column(
                        children: [
                          if (!_isSelectMode) _searchBar(l),
                          _categoryBar(l, allItems, categories),
                          _sortBar(l, visible.length),
                          if (hasSourceError) _errorBanner(l),
                        ],
                      ),
                    ),
                  ),
                  if (visible.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _emptyState(l, hasSourceError),
                    )
                  else ...[
                    _bookSliver(visible, categories, categoryNameById),
                    const SliverPadding(padding: EdgeInsets.only(bottom: 28)),
                  ],
                ],
              ),
            ),
      bottomNavigationBar: _isSelectMode && _selectedBookIds.isNotEmpty
          ? _bottomBar(l, visible)
          : null,
    );
  }

  List<UnifiedShelfItem> _filteredItems(
    List<UnifiedShelfItem> all,
    ShelfCategoriesState categories,
  ) {
    final query = _searchController.text.trim().toLowerCase();
    final result = all.where((item) {
      final assigned = categories.categoryFor(item);
      if (_selectedCategoryId == _uncategorized && assigned != null) {
        return false;
      }
      if (_selectedCategoryId != null &&
          _selectedCategoryId != _uncategorized &&
          assigned != _selectedCategoryId) {
        return false;
      }
      if (query.isEmpty) return true;
      return item.displayBook.title.toLowerCase().contains(query) ||
          (item.displayBook.author?.toLowerCase().contains(query) ?? false);
    }).toList();
    if (_sort != _ShelfSort.defaultOrder) {
      result.sort((a, b) {
        final left = _sort == _ShelfSort.title
            ? a.displayBook.title
            : a.displayBook.author ?? '';
        final right = _sort == _ShelfSort.title
            ? b.displayBook.title
            : b.displayBook.author ?? '';
        return left.toLowerCase().compareTo(right.toLowerCase());
      });
    }
    return result;
  }

  bool _sourceError(AsyncValue<dynamic> library) {
    return library.hasError;
  }

  Widget _appBar(AppLocalizations l, Set<int> visibleIds) {
    if (_isSelectMode) {
      return SliverAppBar(
        pinned: true,
        leading: IconButton(
          tooltip: l.cancel,
          icon: const Icon(Icons.close),
          onPressed: _exitSelectMode,
        ),
        title: Text('${_selectedBookIds.length} ${l.shelfSelected}'),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              if (visibleIds.isNotEmpty &&
                  _selectedBookIds.containsAll(visibleIds)) {
                _selectedBookIds.removeAll(visibleIds);
              } else {
                _selectedBookIds.addAll(visibleIds);
              }
            }),
            child: Text(l.selectAll),
          ),
        ],
      );
    }
    return SliverAppBar(
      pinned: true,
      floating: true,
      title: Text(l.shelfTitle),
      actions: [
        IconButton(
          tooltip: l.shelfManageCategories,
          icon: const Icon(Icons.label_outline_rounded),
          onPressed: _manageCategories,
        ),
        IconButton(
          tooltip: _isListView
              ? l.shelfView
              : l.listView,
          onPressed: () => setState(() => _isListView = !_isListView),
          icon: Icon(
            _isListView ? Icons.grid_view_rounded : Icons.view_list_rounded,
          ),
        ),
      ],
    );
  }

  // 与首页搜索框一致：胶囊形 + 柔和投影，填充色/圆角沿用全局 inputDecorationTheme。
  Widget _searchBar(AppLocalizations l) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? 0.2
                  : 0.06,
            ),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (_) {
          _exitSelectMode();
          setState(() {});
        },
        decoration: InputDecoration(
          hintText: l.shelfSearchHint,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  tooltip: l.clear,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 14,
          ),
        ),
      ),
    ),
  );

  Widget _categoryBar(
    AppLocalizations l,
    List<UnifiedShelfItem> all,
    ShelfCategoriesState state,
  ) {
    final scoped = all;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          _categoryChip(l.shelfAllCategories, null, scoped.length),
          _categoryChip(
            l.shelfUncategorized,
            _uncategorized,
            scoped.where((item) => state.categoryFor(item) == null).length,
          ),
          for (final category in state.categories)
            _categoryChip(
              category.name,
              category.id,
              state.countFor(category.id, scoped),
            ),
          IconButton(
            tooltip: l.shelfNewCategory,
            visualDensity: VisualDensity.compact,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            onPressed: _createCategory,
            icon: const Icon(Icons.add_rounded, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _categoryChip(String name, String? id, int count) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: Center(
      child: ShelfChip(
        label: '$name $count',
        selected: _selectedCategoryId == id,
        dense: true,
        onSelected: () {
          _exitSelectMode();
          setState(() => _selectedCategoryId = id);
        },
      ),
    ),
  );

  Widget _sortBar(AppLocalizations l, int count) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 0, 0, 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '${l.shelfCount(count)} · ${l.shelfLongPressHint}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        PopupMenuButton<_ShelfSort>(
          tooltip: l.shelfSort,
          onSelected: (value) => setState(() => _sort = value),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: _ShelfSort.defaultOrder,
              child: Text(l.shelfSortDefault),
            ),
            PopupMenuItem(
              value: _ShelfSort.title,
              child: Text(l.shelfSortTitle),
            ),
            PopupMenuItem(
              value: _ShelfSort.author,
              child: Text(l.shelfSortAuthor),
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.swap_vert_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 3),
                Text(
                  l.shelfSort,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _errorBanner(AppLocalizations l) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Card(
      child: ListTile(
        leading: const Icon(Icons.wifi_off_rounded),
        title: Text(l.shelfSourceLoadFailed),
        trailing: TextButton(
          onPressed: () {
            ref.read(savedBooksProvider.notifier).loadSavedBooks();
          },
          child: Text(l.retry),
        ),
      ),
    ),
  );

  static const _gridPadding = 16.0;
  static const _gridSpacing = 14.0;

  Widget _bookSliver(
    List<UnifiedShelfItem> items,
    ShelfCategoriesState categories,
    Map<String, String> categoryNameById,
  ) {
    final columns = _shelfColumns;
    final cellWidth =
        (MediaQuery.sizeOf(context).width -
            _gridPadding * 2 -
            _gridSpacing * (columns - 1)) /
        columns;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(_gridPadding, 4, _gridPadding, 12),
      sliver: _isListView
          ? SliverList.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, index) => _listItem(
                items[index],
                categories,
                categoryNameById,
              ),
            )
          : SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: _gridSpacing,
                mainAxisSpacing: 16,
                mainAxisExtent:
                    cellWidth / ShelfGridItem.coverAspectRatio +
                    ShelfGridItem.captionHeight,
              ),
              itemCount: items.length,
              itemBuilder: (_, index) => _gridItem(
                items[index],
                categories,
                categoryNameById,
              ),
            ),
    );
  }

  int get _shelfColumns =>
      ((MediaQuery.sizeOf(context).width - _gridPadding * 2) / 115)
          .floor()
          .clamp(3, 8);

  String? _categoryName(
    UnifiedShelfItem item,
    ShelfCategoriesState categories,
    Map<String, String> categoryNameById,
  ) {
    final id = categories.categoryFor(item);
    if (id == null) return null;
    return categoryNameById[id];
  }

  Widget _gridItem(
    UnifiedShelfItem item,
    ShelfCategoriesState categories,
    Map<String, String> categoryNameById,
  ) {
    final id = _libraryId(item);
    return _ShelfItemTile(
      item: item,
      isListView: false,
      isSelectMode: _isSelectMode,
      isSelected: id != null && _selectedBookIds.contains(id),
      categoryName: _categoryName(item, categories, categoryNameById),
      onTap: () => _onItemTap(item),
      onLongPress: (it, local) {
        if (id == null) {
          _showSingleBookActions(it, local);
        } else {
          _enterSelectMode(id);
        }
      },
    );
  }

  Widget _listItem(
    UnifiedShelfItem item,
    ShelfCategoriesState categories,
    Map<String, String> categoryNameById,
  ) {
    final id = _libraryId(item);
    return _ShelfItemTile(
      item: item,
      isListView: true,
      isSelectMode: _isSelectMode,
      isSelected: id != null && _selectedBookIds.contains(id),
      categoryName: _categoryName(item, categories, categoryNameById),
      onTap: () => _onItemTap(item),
      onLongPress: (it, local) {
        if (id == null) {
          _showSingleBookActions(it, local);
        } else {
          _enterSelectMode(id);
        }
      },
    );
  }

  Widget _emptyState(AppLocalizations l, bool hasSourceError) {
    final searched = _searchController.text.trim().isNotEmpty;
    final filtered = searched || _selectedCategoryId != null;
    final title = hasSourceError
        ? l.shelfSourceLoadFailed
        : filtered
        ? l.shelfNoMatches
        : l.shelfEmpty;
    final message = hasSourceError
        ? l.shelfRetryHint
        : filtered
        ? l.shelfTryOtherFilter
        : l.shelfEmptyMessage;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              filtered ? Icons.search_off_rounded : Icons.auto_stories_outlined,
              size: 54,
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 14),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 7),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: hasSourceError
                  ? () {
                      ref.read(savedBooksProvider.notifier).loadSavedBooks();
                    }
                  : filtered
                  ? () => setState(() {
                      _searchController.clear();
                      _selectedCategoryId = null;
                    })
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SearchScreen(),
                      ),
                    ),
              child: Text(
                hasSourceError
                    ? l.retry
                    : filtered
                    ? l.shelfClearFilters
                    : l.shelfFindBooks,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar(AppLocalizations l, List<UnifiedShelfItem> visible) =>
      DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
              children: [
                _selectionAction(
                  icon: Icons.label_outline_rounded,
                  label: l.shelfAddToCategory,
                  onPressed: () => _showCategoryPicker(
                    visible
                        .where(
                          (item) =>
                              item.source == ShelfSource.library &&
                              _selectedBookIds.contains(
                                int.tryParse(item.rawBookId),
                              ),
                        )
                        .toList(),
                  ),
                ),
                _selectionAction(
                  icon: Icons.delete_outline_rounded,
                  label: l.batchRemove,
                  onPressed: () => _confirmBatchRemove(l),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _selectionAction({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) => Expanded(
    child: TextButton(
      onPressed: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 21),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
  );

  int? _libraryId(UnifiedShelfItem item) =>
      item.source == ShelfSource.library ? int.tryParse(item.rawBookId) : null;

  void _onItemTap(UnifiedShelfItem item) {
    final id = _libraryId(item);
    if (_isSelectMode && id != null) {
      _toggleSelect(id);
      return;
    }
    final book = item.displayBook.original;
    if (book is Book) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const BookDetailScreen(),
          settings: RouteSettings(arguments: book),
        ),
      );
    }
  }

  Future<void> _quickAction(UnifiedShelfItem item, DownloadTask? local) async {
    if (local?.filePath != null) {
      try {
        // MediaStoreFiles.exists understands both plain paths and the
        // content:// URIs of MediaStore-published downloads; File.exists
        // returns false for a content URI and would wrongly report the
        // file as missing.
        if (!await MediaStoreFiles.exists(local!.filePath!)) {
          ref.read(downloadProvider.notifier).markMissingFile(local.id);
          if (mounted) {
            _message(AppLocalizations.of(context)!.downloadFileMissing);
          }
          return;
        }
        // MediaStore-published downloads live at a content:// URI, which
        // OpenFilex cannot open — those go through the platform channel.
        if (MediaStoreFiles.isContentUri(local.filePath!)) {
          final opened = await MediaStoreFiles.open(local.filePath!);
          if (!opened && mounted) {
            _message(AppLocalizations.of(context)!.openFileFailed);
          }
          return;
        }
        final result = await OpenFilex.open(local.filePath!);
        if (result.type == ResultType.done) return;
        if (mounted) _message(result.message);
      } catch (error) {
        if (mounted) _message(error.toString());
      }
      return;
    }
    if (mounted) _onItemTap(item);
  }

  Future<void> _showSingleBookActions(
    UnifiedShelfItem item,
    DownloadTask? local,
  ) async {
    HapticFeedback.mediumImpact();
    final l = AppLocalizations.of(context)!;
    ModalRoute<dynamic>? sheetRoute;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        sheetRoute = ModalRoute.of(sheetContext);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  item.displayBook.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.menu_book_rounded),
                title: Text(
                  local != null
                      ? l.openFile
                      : l.shelfViewDetails,
                ),
                onTap: () => Navigator.pop(sheetContext, 'quick'),
              ),
              ListTile(
                leading: const Icon(Icons.label_outline_rounded),
                title: Text(l.shelfAddToCategory),
                onTap: () => Navigator.pop(sheetContext, 'category'),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: Text(l.shelfViewDetails),
                onTap: () => Navigator.pop(sheetContext, 'detail'),
              ),
            ],
          ),
        );
      },
    );
    await sheetRoute?.completed;
    if (!mounted) return;
    if (action == 'quick') {
      await _quickAction(item, local);
    } else if (action == 'category') {
      await _showCategoryPicker([item]);
    } else if (action == 'detail') {
      _onItemTap(item);
    }
  }

  void _confirmBatchRemove(AppLocalizations l) {
    final ids = _selectedBookIds.map((id) => id.toString()).toList();
    if (ids.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.confirmRemoveTitle),
        content: Text(
          l.confirmRemoveMsg(ids.length),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _batchRemove(ids);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red[400]),
            child: Text(l.remove),
          ),
        ],
      ),
    );
  }

  /// 批量取消收藏：逐本调用接口，全部处理完后只刷新一次收藏列表。
  Future<void> _batchRemove(List<String> ids) async {
    await ref.read(savedBooksProvider.notifier).unsaveBooks(ids);
    if (mounted) _exitSelectMode();
  }

  void _toggleSelect(int id) => setState(() {
    if (!_selectedBookIds.add(id)) _selectedBookIds.remove(id);
  });

  void _enterSelectMode(int id) {
    HapticFeedback.mediumImpact();
    setState(() {
      _isSelectMode = true;
      _selectedBookIds.add(id);
    });
  }

  void _exitSelectMode() {
    if (!_isSelectMode && _selectedBookIds.isEmpty) return;
    setState(() {
      _isSelectMode = false;
      _selectedBookIds.clear();
    });
  }

  Future<String?> _categoryNameDialog({String? initial}) async {
    final l = AppLocalizations.of(context)!;
    var name = initial ?? '';
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<String>(
      context: context,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      builder: (dialogContext) => AlertDialog(
        title: Text(
          initial == null
              ? l.shelfNewCategory
              : l.shelfRenameCategory,
        ),
        content: TextFormField(
          initialValue: initial,
          autofocus: true,
          maxLength: 24,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: l.shelfCategoryName),
          onChanged: (value) => name = value,
          onFieldSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, name),
            child: Text(l.save),
          ),
        ],
      ),
    );
    final result = await navigator.push(route);
    await route.completed;
    return result;
  }

  Future<String?> _createCategory() async {
    final name = await _categoryNameDialog();
    if (name == null || !mounted) return null;
    try {
      await ref.read(shelfCategoriesProvider.notifier).create(name);
      final created = ref.read(shelfCategoriesProvider).categories.last;
      return created.id;
    } catch (error) {
      if (mounted) {
        _message(AppLocalizations.of(context)!.shelfCategoryInvalid);
      }
      return null;
    }
  }

  Future<void> _showCategoryPicker(List<UnifiedShelfItem> items) async {
    if (items.isEmpty) return;
    final l = AppLocalizations.of(context)!;
    final categories = ref.read(shelfCategoriesProvider);
    final current = items.length == 1
        ? categories.categoryFor(items.single)
        : null;
    ModalRoute<dynamic>? sheetRoute;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        sheetRoute = ModalRoute.of(sheetContext);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(title: Text(l.shelfAddToCategory)),
              ListTile(
                leading: const Icon(Icons.remove_circle_outline_rounded),
                title: Text(l.shelfUncategorized),
                trailing: current == null ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(sheetContext, _uncategorized),
              ),
              for (final category in categories.categories)
                ListTile(
                  leading: const Icon(Icons.label_outline_rounded),
                  title: Text(category.name),
                  trailing: current == category.id
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.pop(sheetContext, category.id),
                ),
              ListTile(
                leading: const Icon(Icons.add_rounded),
                title: Text(l.shelfNewCategory),
                onTap: () => Navigator.pop(sheetContext, '__new__'),
              ),
            ],
          ),
        );
      },
    );
    await sheetRoute?.completed;
    if (chosen == null || !mounted) return;
    final id = chosen == '__new__' ? await _createCategory() : chosen;
    if (id == null || !mounted) return;
    try {
      await ref
          .read(shelfCategoriesProvider.notifier)
          .assign(items, id == _uncategorized ? null : id);
      if (mounted) _message(l.shelfCategorySaved);
    } catch (error) {
      if (mounted) _message(l.shelfCategorySaveFailed);
    }
  }

  Future<void> _manageCategories() async {
    final l = AppLocalizations.of(context)!;
    final categories = ref.read(shelfCategoriesProvider).categories;
    ModalRoute<dynamic>? sheetRoute;
    final command = await showModalBottomSheet<_CategoryCommand>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        sheetRoute = ModalRoute.of(sheetContext);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(title: Text(l.shelfManageCategories)),
              for (final category in categories)
                ListTile(
                  leading: const Icon(Icons.label_outline_rounded),
                  title: Text(category.name),
                  trailing: PopupMenuButton<String>(
                    tooltip: l.more,
                    onSelected: (value) {
                      Navigator.pop(
                        sheetContext,
                        _CategoryCommand(value, category),
                      );
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'rename',
                        child: Text(l.shelfRenameCategory),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(l.delete),
                      ),
                    ],
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.add_rounded),
                title: Text(l.shelfNewCategory),
                onTap: () => Navigator.pop(
                  sheetContext,
                  const _CategoryCommand('create'),
                ),
              ),
            ],
          ),
        );
      },
    );
    await sheetRoute?.completed;
    if (!mounted || command == null) return;
    if (command.action == 'create') {
      await _createCategory();
    } else if (command.action == 'rename' && command.category != null) {
      await _renameCategory(command.category!);
    } else if (command.action == 'delete' && command.category != null) {
      await _deleteCategory(command.category!);
    }
  }

  Future<void> _renameCategory(ShelfCategory category) async {
    final name = await _categoryNameDialog(initial: category.name);
    if (name == null || !mounted) return;
    try {
      await ref
          .read(shelfCategoriesProvider.notifier)
          .rename(category.id, name);
    } catch (error) {
      if (mounted) {
        _message(AppLocalizations.of(context)!.shelfCategoryInvalid);
      }
    }
  }

  Future<void> _deleteCategory(ShelfCategory category) async {
    final l = AppLocalizations.of(context)!;
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<bool>(
      context: context,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      builder: (dialogContext) => AlertDialog(
        title: Text(l.shelfDeleteCategory),
        content: Text(l.shelfDeleteCategoryHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    final confirmed = await navigator.push(route);
    await route.completed;
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(shelfCategoriesProvider.notifier).delete(category.id);
      if (mounted && _selectedCategoryId == category.id) {
        setState(() => _selectedCategoryId = null);
      }
    } catch (error) {
      if (mounted) _message(l.shelfCategorySaveFailed);
    }
  }

  void _message(String message) => showAppSnack(context, message);
}

/// One shelf row that watches only its own download task. A progress
/// tick for another book rebuilds neither this tile nor the shelf
/// above it — the parent never watches the download list at all.
/// The completed-only filter replicates the old completedById map:
/// only a finished task with a file counts as downloaded, and only
/// that task is handed to the action sheet / quick-open.
class _ShelfItemTile extends ConsumerWidget {
  const _ShelfItemTile({
    required this.item,
    required this.isListView,
    required this.isSelectMode,
    required this.isSelected,
    required this.categoryName,
    required this.onTap,
    required this.onLongPress,
  });

  final UnifiedShelfItem item;
  final bool isListView;
  final bool isSelectMode;
  final bool isSelected;
  final String? categoryName;
  final VoidCallback onTap;

  /// Called with the item and its completed download task (null when
  /// the book has no finished download).
  final void Function(UnifiedShelfItem, DownloadTask?) onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only library items have a download task; the task id is the
    // book id string. Non-library items never watch a task.
    final DownloadTask? task = item.source == ShelfSource.library
        ? ref.watch(downloadTaskProvider(item.rawBookId))
        : null;
    final DownloadTask? local =
        (task?.status == DownloadStatus.completed && task?.filePath != null)
        ? task
        : null;
    if (isListView) {
      return ShelfListItem(
        item: item,
        isSelectMode: isSelectMode,
        isSelected: isSelected,
        categoryName: categoryName,
        isDownloaded: local != null,
        onTap: onTap,
        onLongPress: () => onLongPress(item, local),
      );
    }
    return ShelfGridItem(
      item: item,
      isSelectMode: isSelectMode,
      isSelected: isSelected,
      categoryName: categoryName,
      isDownloaded: local != null,
      onTap: onTap,
      onLongPress: () => onLongPress(item, local),
    );
  }
}
