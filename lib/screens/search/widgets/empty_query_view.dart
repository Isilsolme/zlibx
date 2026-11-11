import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../providers/trending_provider.dart';
import '../../../services/open_library.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/loading_widget.dart';
import 'recent_searches_section.dart';
import 'trending_section.dart';

/// 从 search_screen 抽出的零状态段：空查询时的落地页 —— 浏览分类 +
/// 近期搜索 + Open Library 热搜。热搜数据由本组件 watch（与原搜索页实现相同的
/// provider），搜索 / 删除历史等行为经回调交回搜索页。
class SearchEmptyQueryView extends ConsumerWidget {
  const SearchEmptyQueryView({
    super.key,
    required this.l10n,
    required this.recentSearches,
    required this.onSearch,
    required this.onRemoveSearch,
    required this.onClearHistory,
    required this.onBrowseCategories,
  });

  final AppLocalizations l10n;
  final List<String> recentSearches;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onRemoveSearch;
  final VoidCallback onClearHistory;
  final VoidCallback onBrowseCategories;

  /// The "Browse Categories" entry row, shown at the top of the empty
  /// view in every state — it is the way into the category tree even
  /// before the first search.
  ListTile _browseCategoriesTile(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(Icons.category_outlined, color: cs.primary),
      title: Text(l10n.browseCategories),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: cs.onSurfaceVariant,
      ),
      onTap: onBrowseCategories,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trendingAsync = ref.watch(trendingBooksProvider);
    final trendingBooks = (trendingAsync.valueOrNull ??
            const <TrendingBookData>[])
        .where((book) => book.title?.trim().isNotEmpty ?? false)
        .toList();
    if (recentSearches.isEmpty && trendingBooks.isEmpty) {
      if (trendingAsync.isLoading) {
        return const LoadingWidget.page(padding: EdgeInsets.all(24));
      }
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _browseCategoriesTile(context),
          ),
          Expanded(
            child: EmptyState(
              icon: Icons.search_rounded,
              title: l10n.startSearching,
              message: l10n.enterSearchHint,
            ),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _browseCategoriesTile(context),
        const SizedBox(height: 16),
        if (recentSearches.isNotEmpty)
          SearchRecentSearchesSection(
            l10n: l10n,
            searches: recentSearches,
            onSearch: onSearch,
            onRemove: onRemoveSearch,
            onClear: onClearHistory,
          ),
        if (trendingBooks.isNotEmpty) ...[
          if (recentSearches.isNotEmpty) const SizedBox(height: 28),
          SearchTrendingSection(
            l10n: l10n,
            books: trendingBooks,
            onSearch: onSearch,
          ),
        ],
      ],
    );
  }
}
