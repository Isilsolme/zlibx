import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nav_label_mode.dart';
import '../providers/settings_provider.dart';
import '../theme/app_layout.dart';
import 'liquid_nav_bar.dart' show LiquidNavDestination;

/// Vertical navigation rail used at tablet/desktop widths.
///
/// This is deliberately *not* the liquid-glass bar: the rail is an opaque M3
/// surface docked to the left edge, with the standard pill indicator, so the
/// content keeps the full height of the window and the glass effects (blur,
/// refraction, hide-on-scroll) stay a phone-only concern. Only the label
/// mode is shared with the bottom bar.
class AppNavRail extends ConsumerWidget {
  const AppNavRail({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  }) : assert(destinations.length > 1, 'needs at least two destinations');

  final List<LiquidNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final labelMode = ref.watch(navLabelModeProvider);

    final labelType = switch (labelMode) {
      NavLabelMode.always => NavigationRailLabelType.all,
      // `auto` keeps the selected label visible, which is the rail
      // equivalent of "only the active tab is labelled".
      NavLabelMode.auto => NavigationRailLabelType.selected,
      NavLabelMode.never => NavigationRailLabelType.none,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(
          right: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        right: false,
        child: NavigationRail(
          selectedIndex: selectedIndex,
          onDestinationSelected: onSelected,
          labelType: labelType,
          minWidth: AppLayout.navRailMinWidth,
          backgroundColor: Colors.transparent,
          indicatorColor: cs.secondaryContainer,
          leading: Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 16),
            child: Icon(
              Icons.auto_stories_rounded,
              size: 28,
              color: cs.primary,
            ),
          ),
          destinations: <NavigationRailDestination>[
            for (final d in destinations)
              NavigationRailDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: Text(d.label),
              ),
          ],
        ),
      ),
    );
  }
}
