import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/settings_provider.dart';
import '../../../widgets/liquid_nav_bar.dart';

/// Watches only the navigation-bar settings, so hide-on-scroll and theme
/// changes never rebuild the PageView (and its kept-alive tab pages).
class HomeNavBar extends ConsumerWidget {
  const HomeNavBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.pageController,
    required this.onSelected,
  });

  final List<LiquidNavDestination> destinations;
  final int selectedIndex;
  final PageController pageController;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final floating = ref.watch(floatingNavProvider);
    final blurEnabled = ref.watch(blurEnabledProvider);
    final refraction = ref.watch(glassRefractionProvider);
    final labelMode = ref.watch(navLabelModeProvider);
    final hideOnScroll = ref.watch(hideNavOnScrollProvider);
    final navVisible = ref.watch(navBarVisibleProvider);
    final hideEnabled = floating && hideOnScroll;
    return RepaintBoundary(
      child: LiquidNavBar(
        destinations: destinations,
        selectedIndex: selectedIndex,
        pageController: pageController,
        onSelected: onSelected,
        blurEnabled: blurEnabled,
        floating: floating,
        refractionEnabled: refraction,
        labelMode: labelMode,
        visible: !hideEnabled || navVisible,
      ),
    );
  }
}
