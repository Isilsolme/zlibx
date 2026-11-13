import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/zlibrary_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/booklist_warmup.dart';
import '../../widgets/keep_alive_page.dart';
import '../account/account_screen.dart';
import '../downloads/local_downloads_screen.dart';
import '../settings/settings_screen.dart';

import '../../theme/app_layout.dart';
import '../../theme/app_metrics.dart';
import '../../widgets/app_nav_rail.dart';
import 'home_tab.dart';
import 'widgets/home_nav_bar.dart';
import 'widgets/nav_destinations.dart';

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
    // Fire-and-forget: warm the booklist pages' challenge solver in
    // the background so opening a booklist later skips the solve. The
    // home screen is the single funnel for signed-in entry (fresh
    // login and restored session both land here); the warm-up itself
    // is single-flight per launch, headless only, and silent on
    // failure.
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
    // Coolapk-style persistent tabs: all four destinations live in one
    // PageView under the same navigation (search is still opened from
    // the home search box, no nav tab). The first destination is
    // Recommended (the home tab, showing the recommendations); tapping
    // it scrolls the grid to the top.
    //
    // Phones keep the floating liquid-glass bar at the bottom; tablets and
    // wide windows move the same destinations into an opaque vertical rail
    // on the left, so the content gets the full height and the glass stays
    // a phone-only effect.
    final useRail = AppLayout.usesNavRail(context);

    final tabs = NotificationListener<ScrollNotification>(
      onNotification: _onTabScroll,
      child: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) {
          // Switching tabs resets the nav to visible: a home tab
          // scrolled down must not leave the bar hidden on Settings.
          if (ref.read(navBarVisibleProvider) != true) {
            ref.read(navBarVisibleProvider.notifier).setVisible(true);
          }
          setState(() => _selectedIndex = index);
          if (index == 0) {
            _homeTabKey.currentState?.onBecameVisible();
          }
        },
        itemCount: 4,
        itemBuilder: (context, index) {
          // The builder only runs for the visible page and the
          // adjacent pages PageView prebuilds, so tabs the user has
          // not visited yet are not constructed at first frame.
          // Once built, each page stays alive via KeepAlivePage.
          if (index == 0) {
            return KeepAlivePage(
              // No extra padding here: the home grid reserves the nav
              // clearance (bar on phones, rail on tablets) itself.
              child: HomeTab(key: _homeTabKey),
            );
          }
          // No outer bottom padding on these tabs either: each tab
          // reserves the nav clearance inside its own scrollable, so items
          // scroll behind the floating pill on phones instead of stopping
          // at a fixed blank band above it.
          if (index == 1) {
            return const KeepAlivePage(child: LocalDownloadsScreen());
          }
          if (index == 2) {
            return const KeepAlivePage(child: AccountScreen());
          }
          return const KeepAlivePage(child: SettingsScreen());
        },
      ),
    );

    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectedIndex != 0) {
          _pageController.animateToPage(
            0,
            duration: AppMotion.slow,
            curve: Curves.easeInOut,
          );
        }
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        // The rail is a sibling of the pages, so on wide layouts nothing
        // extends behind the navigation and the system insets stay intact.
        extendBody: !useRail,
        body: useRail
            ? Row(
                children: <Widget>[
                  AppNavRail(
                    destinations: homeDestinations(context),
                    selectedIndex: _selectedIndex,
                    onSelected: _onDestinationSelected,
                  ),
                  Expanded(child: tabs),
                ],
              )
            : tabs,
        bottomNavigationBar: useRail
            ? null
            : HomeNavBar(
                selectedIndex: _selectedIndex,
                onDestinationSelected: _onDestinationSelected,
                pageController: _pageController,
              ),
      ),
    );
  }

  /// Hide-on-scroll for the Downloads / Account / Settings tabs. The
  /// Recommended tab drives the same provider from its own controller
  /// (see HomeTabState._onScroll), so it is skipped here. Only vertical
  /// scrolling counts: the PageView's own horizontal swipes and the
  /// Downloads TabBarView must not toggle the bar.
  bool _onTabScroll(ScrollNotification n) {
    // The rail never hides, so there is nothing to drive on wide layouts.
    if (AppLayout.usesNavRail(context)) return false;
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
    // The selected index follows the page (onPageChanged); tapping the
    // current tab leaves the page animation a no-op.
    _pageController.animateToPage(
      index,
      duration: AppMotion.slow,
      curve: Curves.easeInOut,
    );
  }
}
