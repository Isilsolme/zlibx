import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/settings_provider.dart';
import '../../../l10n/app_localizations.dart';
import 'section_header.dart';
import 'settings_card.dart';

/// Appearance entry — same chevron-tile shape as the other settings.
/// Tapping it opens the appearance popup (same AlertDialog style as the
/// network-line picker); the row's subtitle summarises the current
/// theme, blur and floating-bar state.
class ThemeSection extends ConsumerWidget {
  const ThemeSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final blurEnabled = ref.watch(blurEnabledProvider);
    final floatingNav = ref.watch(floatingNavProvider);
    final t = AppLocalizations.of(context);

    final summary = <String>[
      switch (themeMode) {
        AppThemeMode.system => t.get('system'),
        AppThemeMode.dark => t.get('dark'),
        AppThemeMode.light => t.get('light'),
      },
      if (blurEnabled) t.get('blur_effect'),
      if (floatingNav) t.get('floating_nav'),
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          icon: Icons.palette_rounded,
          title: t.get('appearance'),
        ),
        SettingsCard(
          child: ListTile(
            leading: const Icon(Icons.palette_rounded),
            title: Text(t.get('appearance')),
            subtitle: Text(summary),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showDialog(
              context: context,
              builder: (_) => const AppearanceDialog(),
            ),
          ),
        ),
      ],
    );
  }
}

/// Appearance popup — the five switches (follow system, dark mode, blur
/// effect, floating bar, hide on scroll), in the same AlertDialog style
/// as the network-line picker.
class AppearanceDialog extends ConsumerWidget {
  const AppearanceDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final blurEnabled = ref.watch(blurEnabledProvider);
    final floatingNav = ref.watch(floatingNavProvider);
    final hideNavOnScroll = ref.watch(hideNavOnScrollProvider);
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final followingSystem = themeMode == AppThemeMode.system;

    return AlertDialog(
      title: Text(t.get('appearance')),
      contentPadding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              title: Text(t.get('system')),
              value: followingSystem,
              activeColor: cs.primary,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              onChanged: (value) {
                ref.read(themeModeProvider.notifier).setThemeMode(
                      value ? AppThemeMode.system : AppThemeMode.light,
                    );
              },
            ),
            SwitchListTile(
              title: Text(t.get('dark_mode')),
              value: themeMode == AppThemeMode.dark,
              activeColor: cs.primary,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              onChanged: followingSystem
                  ? null
                  : (value) {
                      ref.read(themeModeProvider.notifier).setThemeMode(
                            value ? AppThemeMode.dark : AppThemeMode.light,
                          );
                    },
            ),
            SwitchListTile(
              title: Text(t.get('blur_effect')),
              value: blurEnabled,
              activeColor: cs.primary,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              onChanged: (value) {
                ref.read(blurEnabledProvider.notifier).setBlurEnabled(value);
              },
            ),
            SwitchListTile(
              title: Text(t.get('floating_nav')),
              value: floatingNav,
              activeColor: cs.primary,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              onChanged: (value) {
                ref.read(floatingNavProvider.notifier).setFloatingNav(value);
              },
            ),
            SwitchListTile(
              title: Text(t.get('hide_nav_on_scroll')),
              value: hideNavOnScroll,
              activeColor: cs.primary,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              onChanged: floatingNav
                  ? (value) {
                      ref
                          .read(hideNavOnScrollProvider.notifier)
                          .setHideNavOnScroll(value);
                    }
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.get('close')),
        ),
      ],
    );
  }
}
