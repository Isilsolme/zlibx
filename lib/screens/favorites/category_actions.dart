import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../models/unified_shelf_item.dart';
import '../../providers/shelf_categories_provider.dart';

/// Sentinel category id meaning "no category": the shelf's
/// uncategorized filter and the picker's uncategorized row.
const kShelfUncategorizedId = '__uncategorized__';

/// The screen hooks the category flows need. Implemented by the
/// favorites screen's State: the flows run across async gaps, so every
/// context / l10n / snack touch after an await goes through here
/// instead of holding a BuildContext.
abstract class ShelfCategoryHost {
  bool get mounted;

  BuildContext get context;

  WidgetRef get ref;

  AppLocalizations l10n();

  void showMessage(String message);

  /// Called after a category was deleted; the screen drops a filter
  /// selection that pointed at it.
  void onCategoryDeleted(String categoryId);
}

/// 从 favorites_screen 抽出的分类操作流：新建、重命名、删除、把书
/// 分配进分类、管理面板。对话框与 shelfCategoriesProvider 的调用都收
/// 在这里；收藏页 State 只留选择模式与数据编排。
class ShelfCategoryActions {
  ShelfCategoryActions(this._host);

  final ShelfCategoryHost _host;

  Future<String?> createCategory() async {
    final name = await _categoryNameDialog(_host.context);
    if (name == null || !_host.mounted) return null;
    try {
      await _host.ref.read(shelfCategoriesProvider.notifier).create(name);
      final created = _host.ref.read(shelfCategoriesProvider).categories.last;
      return created.id;
    } catch (error) {
      if (_host.mounted) {
        _host.showMessage(_host.l10n().shelfCategoryInvalid);
      }
      return null;
    }
  }

  Future<void> showCategoryPicker(List<UnifiedShelfItem> items) async {
    if (items.isEmpty) return;
    final l = _host.l10n();
    final categories = _host.ref.read(shelfCategoriesProvider);
    final current = items.length == 1
        ? categories.categoryFor(items.single)
        : null;
    ModalRoute<dynamic>? sheetRoute;
    final chosen = await showModalBottomSheet<String>(
      context: _host.context,
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
                onTap: () =>
                    Navigator.pop(sheetContext, kShelfUncategorizedId),
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
    if (chosen == null || !_host.mounted) return;
    final id = chosen == '__new__' ? await createCategory() : chosen;
    if (id == null || !_host.mounted) return;
    try {
      await _host.ref
          .read(shelfCategoriesProvider.notifier)
          .assign(items, id == kShelfUncategorizedId ? null : id);
      if (_host.mounted) _host.showMessage(l.shelfCategorySaved);
    } catch (error) {
      if (_host.mounted) _host.showMessage(l.shelfCategorySaveFailed);
    }
  }

  Future<void> manageCategories() async {
    final l = _host.l10n();
    final categories = _host.ref.read(shelfCategoriesProvider).categories;
    ModalRoute<dynamic>? sheetRoute;
    final command = await showModalBottomSheet<_CategoryCommand>(
      context: _host.context,
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
    if (!_host.mounted || command == null) return;
    if (command.action == 'create') {
      await createCategory();
    } else if (command.action == 'rename' && command.category != null) {
      await _renameCategory(command.category!);
    } else if (command.action == 'delete' && command.category != null) {
      await _deleteCategory(command.category!);
    }
  }

  Future<void> _renameCategory(ShelfCategory category) async {
    final name = await _categoryNameDialog(
      _host.context,
      initial: category.name,
    );
    if (name == null || !_host.mounted) return;
    try {
      await _host.ref
          .read(shelfCategoriesProvider.notifier)
          .rename(category.id, name);
    } catch (error) {
      if (_host.mounted) {
        _host.showMessage(_host.l10n().shelfCategoryInvalid);
      }
    }
  }

  Future<void> _deleteCategory(ShelfCategory category) async {
    final l = _host.l10n();
    final navigator = Navigator.of(_host.context, rootNavigator: true);
    final route = DialogRoute<bool>(
      context: _host.context,
      themes: InheritedTheme.capture(from: _host.context, to: navigator.context),
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
    if (confirmed != true || !_host.mounted) return;
    try {
      await _host.ref
          .read(shelfCategoriesProvider.notifier)
          .delete(category.id);
      _host.onCategoryDeleted(category.id);
    } catch (error) {
      if (_host.mounted) _host.showMessage(l.shelfCategorySaveFailed);
    }
  }
}

class _CategoryCommand {
  const _CategoryCommand(this.action, [this.category]);

  final String action;
  final ShelfCategory? category;
}

Future<String?> _categoryNameDialog(
  BuildContext context, {
  String? initial,
}) async {
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
