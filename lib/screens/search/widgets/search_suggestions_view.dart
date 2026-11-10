import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/loading_widget.dart';

/// 从 search_screen 抽出的零状态段：输入中的服务器建议列表。匹配
/// 前缀高亮；点击建议即搜索（[onSearch]），尾箭头只填入不搜索
/// （[onInsert]）。
class SearchSuggestionsView extends StatelessWidget {
  const SearchSuggestionsView({
    super.key,
    required this.l10n,
    required this.suggestions,
    required this.isLoading,
    required this.query,
    required this.onSearch,
    required this.onInsert,
  });

  final AppLocalizations l10n;
  final List<String> suggestions;
  final bool isLoading;
  final String query;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onInsert;

  @override
  Widget build(BuildContext context) {
    if (isLoading && suggestions.isEmpty) {
      return const LoadingWidget.page(padding: EdgeInsets.all(24));
    }
    if (suggestions.isEmpty) {
      return EmptyState(
        icon: Icons.search_rounded,
        title: l10n.startSearching,
        message: l10n.enterSearchHint,
      );
    }
    final cs = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
      itemCount: suggestions.length,
      itemBuilder: (context, index) {
        final suggestion = suggestions[index];
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onSearch(suggestion),
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
                  child: _highlightedText(context, suggestion, query),
                ),
                IconButton(
                  icon: Icon(
                    Icons.north_west_rounded,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                  onPressed: () => onInsert(suggestion),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _highlightedText(
    BuildContext context,
    String suggestion,
    String query,
  ) {
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
}
