import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/settings_provider.dart';
import '../../../l10n/app_localizations.dart';
import 'section_header.dart';
import 'settings_card.dart';

/// Appearance options as a uniform set of switches, matching the other
/// settings rows. Theme is two switches: follow system, and dark mode
/// (disabled while following the system).
class ThemeSection extends ConsumerWidget {
  const ThemeSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final blurEnabled = ref.watch(blurEnabledProvider);
    final floatingNav = ref.watch(floatingNavProvider);
    final hideNavOnScroll = ref.watch(hideNavOnScrollProvider);
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final followingSystem = themeMode == AppThemeMode.system;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          icon: Icons.palette_rounded,
          title: t.get('appearance'),
        ),
        SettingsCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Column(
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
                  ref
                      .read(floatingNavProvider.notifier)
                      .setFloatingNav(value);
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
      ],
    );
  }
}
