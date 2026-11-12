import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/s_keys.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/zlibrary_provider.dart';
import '../../services/booklist_warmup.dart';
import '../../widgets/keep_alive_page.dart';
import '../../widgets/liquid_nav_bar.dart';
import '../account/account_screen.dart';
import '../downloads/local_downloads_screen.dart';
import '../settings/settings_screen.dart';
import 'widgets/home_nav_bar.dart';
import 'widgets/home_tab.dart';

/// Four persistent destinations in one PageView. The Recommended tab owns
/// the feed/header/lifecycle logic (see [HomeTab]); this host only wires
/// navigation, the hide-on-scroll policy for non-home tabs, and the warm-up.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedIndex = 0;
  final _homeTabKey = GlobalKey<HomeTabState>();
  final _pageController = PageController();

  @override
  void initState() {
    super.initState();
    // Warm the booklist challenge solver in the background so opening a
    // booklist later skips the solve. Single-flight, headless, silent.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        BooklistWarmup.warmUp(
          api: ref.read(zlibraryApiProvider),
          user: ref.read(authProvider).user,
        ),
      );
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final destinations = <LiquidNavDestination>[
      LiquidNavDestination(
        icon: Icons.local_fire_department_outlined,
        selectedIcon: Icons.local_fire_department,
        label: l10n.get(S.recommended),
      ),
      LiquidNavDestination(
        icon: Icons.cloud_download_outlined,
        selectedIcon: Icons.cloud_download,
        label: l10n.get(S.downloads),
      ),
      LiquidNavDestination(
        icon: Icons.person_outlined,
        selectedIcon: Icons.person,
        label: l10n.get(S.account),
      ),
      LiquidNavDestination(
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        label: l10n.get(S.settings),
      ),
    ];

    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectedIndex != 0 && _pageController.hasClients) {
          _pageController.animateToPage(
            0,
            duration: const Duration(milliseconds: 340),
            curve: Curves.easeOutCubic,
          );
        }
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        extendBody: true,
        body: NotificationListener<ScrollNotification>(
          onNotification: _onTabScroll,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              // Switching tabs resets the nav to visible: a home tab
              // scrolled down must not leave the bar hidden on Settings.
              ref.read(navBarVisibleProvider.notifier).setVisible(true);
              setState(() => _selectedIndex = index);
              if (index == 0) {
                _homeTabKey.currentState?.onBecameVisible();
              }
            },
            itemCount: 4,
            itemBuilder: (context, index) {
              if (index == 0) {
                return KeepAlivePage(child: HomeTab(key: _homeTabKey));
              }
              if (index == 1) {
                return const KeepAlivePage(child: LocalDownloadsScreen());
              }
              if (index == 2) {
                return const KeepAlivePage(child: AccountScreen());
              }
              return const KeepAlivePage(child: SettingsScreen());
            },
          ),
        ),
        bottomNavigationBar: HomeNavBar(
          destinations: destinations,
          selectedIndex: _selectedIndex,
          pageController: _pageController,
          onSelected: _onDestinationSelected,
        ),
      ),
    );
  }

  /// Hide-on-scroll for the Downloads / Account / Settings tabs. The
  /// Recommended tab drives the same provider from its own controller
  /// (see HomeTabState._onScroll), so it is skipped here. Only vertical
  /// scrolling counts: the PageView's swipes and the Downloads TabBarView
  /// must not toggle the bar.
  bool _onTabScroll(ScrollNotification n) {
    if (_selectedIndex == 0 || n.metrics.axis != Axis.vertical) return false;
    final hideEnabled =
        ref.read(floatingNavProvider) && ref.read(hideNavOnScrollProvider);
    if (!hideEnabled) return false;
    void setVisible(bool v) {
      if (ref.read(navBarVisibleProvider) != v) {
        ref.read(navBarVisibleProvider.notifier).setVisible(v);
      }
    }

    if (n.metrics.pixels <= n.metrics.minScrollExtent) {
      setVisible(true);
    } else if (n is UserScrollNotification) {
      if (n.direction == ScrollDirection.reverse) {
        setVisible(false);
      } else if (n.direction == ScrollDirection.forward) {
        setVisible(true);
      }
    }
    return false;
  }

  void _onDestinationSelected(int index) {
    if (index == 0) {
      // Recommended: the home tab, scrolled to the top.
      _homeTabKey.currentState?.scrollToTop();
    }
    if (index == _selectedIndex || !_pageController.hasClients) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }
}
