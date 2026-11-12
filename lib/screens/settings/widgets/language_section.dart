import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/settings_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/locale_utils.dart' as locale_utils;
import 'section_header.dart';
import 'settings_card.dart';

import '../../../l10n/s_keys.dart';

class LanguageSection extends ConsumerWidget {
  const LanguageSection({super.key});

  /// All supported languages with metadata. Only the native name is shown
  /// (legado's language menu does the same; no flags, no English gloss).
  static const allLanguages = {
    'en': {'native': 'English'},
    'zh': {'native': '简体中文'},
    'zh_Hant': {'native': '繁體中文'},
    'ja': {'native': '日本語'},
    'ko': {'native': '한국어'},
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          icon: Icons.translate_rounded,
          title: t.get(S.languageSetting),
        ),
        SettingsCard(
          child: Builder(
            builder: (rowContext) => ListTile(
              leading: const Icon(Icons.language_rounded),
              title: Text(t.get(S.languageSetting)),
              subtitle: Text(_displayName(context, ref.watch(localeProvider))),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showLanguageMenu(rowContext, ref),
            ),
          ),
        ),
      ],
    );
  }

  String _displayName(BuildContext context, Locale? locale) {
    if (locale == null) return AppLocalizations.of(context).get(S.system);
    final key = locale_utils.getLocaleKey(locale);
    if (key == null) return '';
    return allLanguages[key]?['native'] ?? key;
  }

  Future<void> _showLanguageMenu(BuildContext context, WidgetRef ref) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;

    final currentLocale = ref.read(localeProvider);
    final currentKey = currentLocale != null
        ? locale_utils.getLocaleKey(currentLocale)
        : null;
    final t = AppLocalizations.of(context);

    // Anchor the small popup to the right edge of the row, just below it —
    // legado's dropdown behaviour, instead of a full-width bottom sheet.
    final anchor = Rect.fromLTWH(
      (box.size.width - 216).clamp(0.0, box.size.width),
      0,
      box.size.width.clamp(0.0, 216.0),
      box.size.height,
    );
    final global = MatrixUtils.transformRect(
      box.getTransformTo(overlay),
      anchor,
    );

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(global, Offset.zero & overlay.size),
      color: Theme.of(context).colorScheme.surfaceContainer,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 220),
      popUpAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 150),
        reverseDuration: Duration(milliseconds: 100),
      ),
      items: <PopupMenuEntry<String>>[
        _languageItem(context, 'system', t.get(S.system), currentKey == null),
        for (final entry in allLanguages.entries)
          _languageItem(
            context,
            entry.key,
            entry.value['native']!,
            currentKey == entry.key,
          ),
      ],
    );

    if (!context.mounted || selected == null) return;
    if (selected == 'system') {
      ref.read(localeProvider.notifier).setLocale(null);
    } else {
      ref
          .read(localeProvider.notifier)
          .setLocale(locale_utils.parseLocaleKey(selected));
    }
  }

  PopupMenuItem<String> _languageItem(
    BuildContext context,
    String value,
    String label,
    bool selected,
  ) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuItem<String>(
      value: value,
      height: 44,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? cs.primary : cs.onSurface,
              ),
            ),
          ),
          if (selected) Icon(Icons.check_rounded, size: 18, color: cs.primary),
        ],
      ),
    );
  }
}
