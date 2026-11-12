import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/s_keys.dart';
import '../../../models/display_book.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/home_feed_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/update_provider.dart';
import '../../../routes/app_routes.dart';
import '../../../utils/app_snack.dart';
import '../../../widgets/domain_selector.dart';
import '../../../widgets/liquid_nav_bar.dart';
import '../../../widgets/update_dialog.dart';
import '../../book_detail/book_detail_screen.dart';
import 'home_feed_view.dart';
import 'home_header.dart';
import 'home_header_glass.dart';

/// The Recommended tab: glass header over the infinite book grid, plus the
/// scroll/refresh/update lifecycle.
class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key});

  @override
  ConsumerState<HomeTab> createState() => HomeTabState();
}

class HomeTabState extends ConsumerState<HomeTab> with WidgetsBindingObserver {
  final _scrollController = ScrollController();
  double _lastScrollPixels = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
      // A warm cache may be stale; let the normal 15-minute policy decide
      // whether to fetch. A cold, empty feed is already loading and no-ops.
      _maybeAutoRefresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _maybeAutoRefresh();
    }
  }

  /// Called when the user swipes/taps back to the Recommended tab.
  void onBecameVisible() => _maybeAutoRefresh();

  void _maybeAutoRefresh() {
    if (!mounted) return;
    final atTop = !_scrollController.hasClients || _scrollController.offset < 4;
    unawaited(ref.read(homeFeedProvider.notifier).autoRefresh(atTop: atTop));
  }

  /// Drives the floating nav bar's hide-on-scroll and requests the next page
  /// before the user actually reaches the bottom.
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;

    final hideEnabled =
        ref.read(floatingNavProvider) && ref.read(hideNavOnScrollProvider);
    if (!hideEnabled) {
      _setNavVisible(true);
    } else if (position.pixels <= 8) {
      _setNavVisible(true);
    } else {
      final delta = position.pixels - _lastScrollPixels;
      if (delta > 3) {
        _setNavVisible(false);
      } else if (delta < -3) {
        _setNavVisible(true);
      }
    }
    _lastScrollPixels = position.pixels;

    if (position.pixels >= position.maxScrollExtent - 900) {
      unawaited(ref.read(homeFeedProvider.notifier).loadMore());
    }
  }

  void _setNavVisible(bool visible) {
    if (ref.read(navBarVisibleProvider) != visible) {
      ref.read(navBarVisibleProvider.notifier).setVisible(visible);
    }
  }

  /// Scroll the recommendation grid back to the top (used by the
  /// Recommended nav destination).
  void scrollToTop() {
    if (!_scrollController.hasClients || _scrollController.offset <= 0) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _refresh() async {
    try {
      final added = await ref.read(homeFeedProvider.notifier).refresh();
      if (!mounted || added <= 0) return;
      showAppSnack(
        context,
        AppLocalizations.of(
          context,
        ).get(S.homeFeedUpdated).replaceAll('{count}', '$added'),
      );
    } catch (_) {
      if (!mounted) return;
      showAppSnack(context, AppLocalizations.of(context).get(S.refreshFailed));
    }
  }

  Future<void> _checkForUpdates() async {
    final updateNotifier = ref.read(updateProvider.notifier);
    final hasUpdate = await updateNotifier.checkForUpdate();

    if (!hasUpdate || !mounted) return;

    if (ref.read(updateProvider).forceUpdate) {
      showUpdateDialog(context);
    } else if (!updateNotifier.isVersionDismissed()) {
      final latest = ref.read(updateProvider).latestVersion;
      showAppSnackRaw(
        context,
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.system_update, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AppLocalizations.of(
                    context,
                  ).get(S.newVersionFound).replaceAll('{version}', '$latest'),
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: AppLocalizations.of(context).get(S.update),
            textColor: Colors.white,
            onPressed: () => showUpdateDialog(context),
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 6),
          dismissDirection: DismissDirection.horizontal,
        ),
      );
      updateNotifier.dismissUpdate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final cs = Theme.of(context).colorScheme;
    final blurEnabled = ref.watch(blurEnabledProvider);
    final floatingNav = ref.watch(floatingNavProvider);
    final l10n = AppLocalizations.of(context);

    final topInset = authState.lineUnavailable
        ? 0.0
        : MediaQuery.paddingOf(context).top;
    final headerHeight = HomeHeader.heightFor(context, topInset);
    final gridTopPadding = headerHeight + 8;
    final bottomPadding = LiquidNavBar.bottomClearance(
      context,
      floating: floatingNav,
    );

    final headerContent = HomeHeader(
      topInset: topInset,
      userName: user?.name ?? l10n.get(S.reader),
      onSearch: () => Navigator.of(context).pushNamed(AppRoutes.search),
    );
    final header = RepaintBoundary(
      child: HomeHeaderGlass(
        height: headerHeight,
        blurEnabled: blurEnabled,
        surface: cs.surface,
        child: headerContent,
      ),
    );

    return Column(
      children: [
        if (authState.lineUnavailable) _buildLineUnavailableBanner(context),
        Expanded(
          child: Stack(
            children: [
              HomeFeedView(
                scrollController: _scrollController,
                topPadding: gridTopPadding,
                bottomPadding: bottomPadding,
                onRefresh: _refresh,
                onOpenBook: _openBook,
              ),
              Positioned(top: 0, left: 0, right: 0, child: header),
            ],
          ),
        ),
      ],
    );
  }

  /// App-open style: the card cover flies to the detail cover (Hero) while
  /// the detail fades in over the still-opaque grid.
  void _openBook(DisplayBook book) {
    Navigator.of(context).push(
      PageRouteBuilder(
        settings: RouteSettings(
          name: AppRoutes.bookDetail,
          arguments: book.asZLibBook,
        ),
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (context, animation, secondaryAnimation) =>
            const BookDetailScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(opacity: curved, child: child);
        },
      ),
    );
  }

  Widget _buildLineUnavailableBanner(BuildContext context) {
    return Material(
      color: Colors.orange.shade50,
      child: InkWell(
        // DomainNotifier.setDomain handles reverify + cache invalidation
        // internally, so just opening the picker is enough.
        onTap: () => showDomainSelectionSheet(context),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.cloud_off_outlined,
                  color: Colors.orange.shade800,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(
                          context,
                        ).get(S.lineUnavailableCurrent),
                        style: TextStyle(
                          color: Colors.orange.shade900,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        AppLocalizations.of(context).get(S.lineCachedLoginHint),
                        style: TextStyle(
                          color: Colors.orange.shade800,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: Colors.orange.shade700,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
