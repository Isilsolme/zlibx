import 'package:flutter/material.dart';

import '../../l10n/book_categories.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../providers/category_books_provider.dart';
import '../../routes/app_routes.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/gradient_app_bar.dart';

/// The category tree: the 39 top-level groups from
/// [kBookCategoryGroups], each with its subcategories. A group header
/// browses the top category itself; subcategories open their own book
/// list. Each group shows its first 8 subcategories with a "Show all"
/// expander, like the site's own /categories page. No counts: the
/// table carries no counts.
///
/// The search field filters the tree locally (same interaction as
/// the site's /categories search dialog): matching categories are
/// listed flat, each subcategory with its parent group's name as a
/// subtitle (via [kBookCategoryParents]).
class CategoryTreeScreen extends StatefulWidget {
  const CategoryTreeScreen({super.key});

  @override
  State<CategoryTreeScreen> createState() => _CategoryTreeScreenState();
}

class _CategoryTreeScreenState extends State<CategoryTreeScreen> {
  /// Groups whose full subcategory list is shown (past the first 8).
  final Set<int> _expandedGroups = {};

  /// Subcategories shown per group before the "Show all" expander.
  static const int _collapsedCount = 8;

  final TextEditingController _searchController = TextEditingController();

  /// Current local-search query (empty = the full tree).
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context);
    final filtering = _query.trim().isNotEmpty;
    final rows = filtering ? _filteredRows(_query.trim(), locale) : _rows();
    return Scaffold(
      appBar: GradientAppBar(title: l10n.categories),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: _searchBar(l10n),
          ),
          Expanded(
            child: filtering && rows.isEmpty
                ? EmptyState(
                    icon: Icons.search_off_rounded,
                    title: l10n.noResults,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      return switch (row) {
                        _HeaderRow(:final group) => _GroupHeader(
                          name: bookCategoryDisplayName(
                            kBookCategoryGroups[group].top,
                            locale,
                          ),
                          onTap: () => _openBooks(
                            kBookCategoryGroups[group].top,
                            locale,
                          ),
                        ),
                        _SubRow(:final categoryId, :final parentName) =>
                          _SubcategoryRow(
                            name: bookCategoryDisplayName(categoryId, locale),
                            subtitle: parentName,
                            onTap: () => _openBooks(categoryId, locale),
                          ),
                        _ShowAllRow(:final group, :final remaining) =>
                          ListTile(
                            contentPadding: const EdgeInsets.only(
                              left: 32,
                              right: 16,
                            ),
                            dense: true,
                            title: Text(l10n.showAll),
                            trailing: Text(
                              '+$remaining',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            onTap: () => setState(
                              () => _expandedGroups.add(group),
                            ),
                          ),
                      };
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // Capsule search field + soft shadow, matching the booklists page.
  Widget _searchBar(AppLocalizations l10n) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.2 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _searchController,
        builder: (context, value, _) => TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          onChanged: (text) => setState(() => _query = text),
          decoration: InputDecoration(
            hintText: l10n.searchCategories,
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    tooltip: l10n.clear,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                  ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(30),
              borderSide: BorderSide.none,
            ),
            filled: true,
          ),
        ),
      ),
    );
  }

  /// The flat row list for the current expanded state: one header per
  /// group, then its visible subcategories, then a "Show all" row when
  /// the group is collapsed and has more than [_collapsedCount] subs.
  List<_TreeRow> _rows() {
    final rows = <_TreeRow>[];
    for (var i = 0; i < kBookCategoryGroups.length; i++) {
      final group = kBookCategoryGroups[i];
      rows.add(_HeaderRow(i));
      final subs = group.subs;
      final expanded = _expandedGroups.contains(i);
      final visible = expanded ? subs : subs.take(_collapsedCount);
      for (final id in visible) {
        rows.add(_SubRow(id));
      }
      if (!expanded && subs.length > _collapsedCount) {
        rows.add(_ShowAllRow(i, subs.length - _collapsedCount));
      }
    }
    return rows;
  }

  /// The flat row list for a local-search query: every matching
  /// category, in tree order, with no "Show all" cap (all matches
  /// show). A match is a localized display name — or the English
  /// name — containing the query. Each matching subcategory carries
  /// its parent group's name as a subtitle, resolved through
  /// [kBookCategoryParents].
  List<_TreeRow> _filteredRows(String query, Locale locale) {
    final needle = query.toLowerCase();
    bool matches(int id) {
      final display = bookCategoryDisplayName(id, locale).toLowerCase();
      if (display.contains(needle)) return true;
      final english = (kBookCategoryEnglishNames[id] ?? '').toLowerCase();
      return english.contains(needle);
    }

    final rows = <_TreeRow>[];
    for (var i = 0; i < kBookCategoryGroups.length; i++) {
      final group = kBookCategoryGroups[i];
      if (matches(group.top)) rows.add(_HeaderRow(i));
      for (final id in group.subs) {
        if (!matches(id)) continue;
        final parentId = kBookCategoryParents[id];
        rows.add(
          _SubRow(
            id,
            parentName: parentId == null
                ? null
                : bookCategoryDisplayName(parentId, locale),
          ),
        );
      }
    }
    return rows;
  }

  void _openBooks(int categoryId, Locale locale) {
    AppRoutes.openCategoryBooks(
      context,
      CategoryBooksArgs(
        categoryId: categoryId,
        categoryName: bookCategoryDisplayName(categoryId, locale),
      ),
    );
  }
}

/// One flat row of the tree list.
sealed class _TreeRow {
  const _TreeRow();
}

/// A top-level group's header row; [group] is its index in
/// [kBookCategoryGroups].
class _HeaderRow extends _TreeRow {
  const _HeaderRow(this.group);

  final int group;
}

/// One subcategory row. [parentName] is set only in the filtered
/// view, where it renders as a subtitle under the name.
class _SubRow extends _TreeRow {
  const _SubRow(this.categoryId, {this.parentName});

  final int categoryId;
  final String? parentName;
}

/// The "Show all" expander of a collapsed group; [remaining] is how
/// many subcategories it hides.
class _ShowAllRow extends _TreeRow {
  const _ShowAllRow(this.group, this.remaining);

  final int group;
  final int remaining;
}

/// A top-level group's header: tapping it browses the group itself.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      title: Text(
        name,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}

/// One subcategory row, indented under its group header.
class _SubcategoryRow extends StatelessWidget {
  const _SubcategoryRow({
    required this.name,
    required this.onTap,
    this.subtitle,
  });

  final String name;
  final VoidCallback onTap;

  /// Parent group's name, shown only in the filtered view.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 32, right: 16),
      dense: true,
      title: Text(name),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: Icon(
        Icons.chevron_right_rounded,
        size: 20,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}
