import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/s_keys.dart';

/// Applies a filter immediately (the sheet stays open and the grid behind it
/// updates), so callbacks fire per selection rather than on dismiss.
Future<void> showSearchFilterSheet(
  BuildContext context, {
  required AppLocalizations l10n,
  required Map<String, String> languageNames,
  required Map<String, String> orderNames,
  required Map<String, String> extensionNames,
  required String language,
  required String order,
  required String extension,
  required ValueChanged<String> onLanguageSelected,
  required ValueChanged<String> onOrderSelected,
  required ValueChanged<String> onExtensionSelected,
  required VoidCallback onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => SearchFilterSheet(
      l10n: l10n,
      languageNames: languageNames,
      orderNames: orderNames,
      extensionNames: extensionNames,
      language: language,
      order: order,
      extension: extension,
      onLanguageSelected: onLanguageSelected,
      onOrderSelected: onOrderSelected,
      onExtensionSelected: onExtensionSelected,
      onChanged: onChanged,
    ),
  );
}

class SearchFilterSheet extends StatefulWidget {
  const SearchFilterSheet({
    super.key,
    required this.l10n,
    required this.languageNames,
    required this.orderNames,
    required this.extensionNames,
    required this.language,
    required this.order,
    required this.extension,
    required this.onLanguageSelected,
    required this.onOrderSelected,
    required this.onExtensionSelected,
    required this.onChanged,
  });

  final AppLocalizations l10n;
  final Map<String, String> languageNames;
  final Map<String, String> orderNames;
  final Map<String, String> extensionNames;
  final String language;
  final String order;
  final String extension;
  final ValueChanged<String> onLanguageSelected;
  final ValueChanged<String> onOrderSelected;
  final ValueChanged<String> onExtensionSelected;
  final VoidCallback onChanged;

  @override
  State<SearchFilterSheet> createState() => _SearchFilterSheetState();
}

class _SearchFilterSheetState extends State<SearchFilterSheet> {
  late String _language = widget.language;
  late String _order = widget.order;
  late String _extension = widget.extension;

  void _selectLanguage(String value) {
    setState(() => _language = value);
    widget.onLanguageSelected(value);
    widget.onChanged();
  }

  void _selectOrder(String value) {
    setState(() => _order = value);
    widget.onOrderSelected(value);
    widget.onChanged();
  }

  void _selectExtension(String value) {
    setState(() => _extension = value);
    widget.onExtensionSelected(value);
    widget.onChanged();
  }

  void _reset() {
    setState(() {
      _language = 'all';
      _order = 'default';
      _extension = 'all';
    });
    widget.onLanguageSelected('all');
    widget.onOrderSelected('default');
    widget.onExtensionSelected('all');
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = widget.l10n;

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
                  backgroundColor: cs.surfaceContainerHigh,
                  side: BorderSide.none,
                  labelStyle: TextStyle(
                    color: selected == entry.key
                        ? cs.onPrimaryContainer
                        : cs.onSurfaceVariant,
                    fontWeight: selected == entry.key
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                  onSelected: (_) => onSelected(entry.key),
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
              l10n.get(S.language),
              widget.languageNames,
              _language,
              _selectLanguage,
            ),
            section(l10n.get(S.sort), widget.orderNames, _order, _selectOrder),
            section(null, widget.extensionNames, _extension, _selectExtension),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _reset,
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  label: Text(l10n.get(S.searchHistoryClear)),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.get(S.close)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
