import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';

/// 从 search_screen 抽出的零状态段：镜像筛选面板当前选择的可删除
/// chips —— 删一个即重置该筛并重新搜索（经 onReset* 回调交回
/// 搜索页）。
class SearchActiveFilterChips extends StatelessWidget {
  const SearchActiveFilterChips({
    super.key,
    required this.l10n,
    required this.languageNames,
    required this.orderNames,
    required this.extensionNames,
    required this.selectedLanguage,
    required this.selectedOrder,
    required this.selectedExtension,
    required this.onResetLanguage,
    required this.onResetOrder,
    required this.onResetExtension,
  });

  final AppLocalizations l10n;
  final Map<String, String> languageNames;
  final Map<String, String> orderNames;
  final Map<String, String> extensionNames;
  final String selectedLanguage;
  final String selectedOrder;
  final String selectedExtension;
  final VoidCallback onResetLanguage;
  final VoidCallback onResetOrder;
  final VoidCallback onResetExtension;

  @override
  Widget build(BuildContext context) {
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

    if (selectedLanguage != 'all') {
      addChip(
        '${l10n.language}: ${languageNames[selectedLanguage]}',
        onResetLanguage,
      );
    }
    if (selectedOrder != 'default') {
      addChip(
        '${l10n.sort}: ${orderNames[selectedOrder]}',
        onResetOrder,
      );
    }
    if (selectedExtension != 'all') {
      addChip(
        '${extensionNames[selectedExtension]}',
        onResetExtension,
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
}
