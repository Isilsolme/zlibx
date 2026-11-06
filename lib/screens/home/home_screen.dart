import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/books_provider.dart';
import '../../providers/zlibrary_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/update_service.dart';
import '../../widgets/book_card.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/domain_selector.dart';
import '../../widgets/update_dialog.dart';
import '../../models/display_book.dart';
import '../../routes/app_routes.dart';
import '../../l10n/app_localizations.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedIndex = 0;
  final _homeTabKey = GlobalKey<_HomeTabState>();

  // Only the home tab lives in the stack; bookshelf/downloads/settings
  // are pushed as routes, and search is opened from the home search box
  // (no nav tab). The first destination is Recommended (the home tab,
  // showing the recommendations); tapping it scrolls the grid to the top.
  late final List<Widget> _screens = [
    _HomeTab(key: _homeTabKey),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final blurEnabled = ref.watch(blurEnabledProvider);
    final floatingNav = ref.watch(floatingNavProvider);
    final hideNavOnScroll = ref.watch(hideNavOnScrollProvider);
    final navVisible = ref.watch(navBarVisibleProvider);
    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      body: _screens[_selectedIndex],
      bottomNavigationBar: _buildNavBar(
        context,
        cs,
        blurEnabled,
        floatingNav,
        hideNavOnScroll,
        navVisible,
      ),
    );
  }

  Widget _buildNavBar(
    BuildContext context,
    ColorScheme cs,
    bool blurEnabled,
    bool floatingNav,
    bool hideNavOnScroll,
    bool navVisible,
  ) {
    // Coolapk-style destinations: the selected tab gets a primaryContainer
    // pill that wraps both the icon and the label (the fork's
    // LiquidNavigationBar does the same), instead of the M3 NavigationBar
    // indicator which only wraps the icon.
    const destinations = [
      (
        icon: Icons.local_fire_department_outlined,
        selectedIcon: Icons.local_fire_department,
        labelKey: 'recommended',
      ),
      (
        icon: Icons.library_books_outlined,
        selectedIcon: Icons.library_books,
        labelKey: 'bookshelf',
      ),
      (
        icon: Icons.cloud_download_outlined,
        selectedIcon: Icons.cloud_download,
        labelKey: 'downloads',
      ),
      (
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        labelKey: 'settings',
      ),
    ];

    Widget navBar = Container(
      decoration: BoxDecoration(
        color: blurEnabled ? cs.surface.withValues(alpha: 0.7) : cs.surface,
        border: floatingNav
            ? null
            : Border(
                top: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
      ),
      child: SizedBox(
        height: 80,
        child: Row(
          children: [
            for (var i = 0; i < destinations.length; i++)
              Expanded(
                child: Stack(
                  children: [
                    if (_selectedIndex == i)
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 4,
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(40),
                            ),
                          ),
                        ),
                      ),
                    Positioned.fill(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _onDestinationSelected(context, i),
                          borderRadius: BorderRadius.circular(40),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _selectedIndex == i
                                    ? destinations[i].selectedIcon
                                    : destinations[i].icon,
                                color: _selectedIndex == i
                                    ? cs.onPrimaryContainer
                                    : cs.onSurfaceVariant,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                AppLocalizations.of(
                                  context,
                                ).get(destinations[i].labelKey),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: _selectedIndex == i
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: _selectedIndex == i
                                      ? cs.onPrimaryContainer
                                      : cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
    if (!blurEnabled) {
      navBar = _wrapNavBar(navBar, floatingNav);
    } else {
      navBar = ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: navBar,
        ),
      );
      navBar = _wrapNavBar(navBar, floatingNav);
    }
    // Hide on scroll down only applies to the floating bar; when the
    // feature is off the bar is always shown, whatever the transient
    // scroll state says.
    final hideEnabled = floatingNav && hideNavOnScroll;
    return AnimatedSlide(
      offset:
          hideEnabled && !navVisible ? const Offset(0, 1.5) : Offset.zero,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: navBar,
    );
  }

  void _onDestinationSelected(BuildContext context, int index) {
    if (index == 0) {
      // Recommended: the home tab, scrolled to the top.
      _homeTabKey.currentState?.scrollToTop();
      setState(() => _selectedIndex = 0);
    } else if (index == 1) {
      Navigator.of(context).pushNamed(AppRoutes.favorites);
    } else if (index == 2) {
      Navigator.of(context).pushNamed(AppRoutes.downloads);
    } else if (index == 3) {
      Navigator.of(context).pushNamed(AppRoutes.settings);
    }
  }

  /// Floating style: detach the bar from the bottom edge as a rounded
  /// pill with a soft shadow. Non-floating keeps the full-width bar.
  /// Radius is half the NavigationBar height (80dp), i.e. a full pill —
  /// the same shape as Coolapk's floating bar (the c001apk fork's
  /// LiquidNavigationBar uses BorderRadius.circular(height / 2)).
  Widget _wrapNavBar(Widget navBar, bool floatingNav) {
    if (!floatingNav) return navBar;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: navBar,
      ),
    );
  }
}

/// Get time-based greeting message
String _getGreeting(BuildContext context) {
  final hour = DateTime.now().hour;
  final locale = Localizations.localeOf(context).languageCode;
  final isZh = locale == 'zh';

  if (hour < 6) {
    return isZh ? '夜深了，' : 'Late night,';
  } else if (hour < 12) {
    return isZh ? '早上好，' : 'Good morning,';
  } else if (hour < 14) {
    return isZh ? '中午好，' : 'Good afternoon,';
  } else if (hour < 18) {
    return isZh ? '下午好，' : 'Good afternoon,';
  } else if (hour < 22) {
    return isZh ? '晚上好，' : 'Good evening,';
  } else {
    return isZh ? '夜深了，' : 'Late night,';
  }
}

class _HomeTab extends ConsumerStatefulWidget {
  const _HomeTab({super.key});

  @override
  ConsumerState<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<_HomeTab> {
  final _scrollController = ScrollController();

  /// Current popular-books page (0 = showing the personalised
  /// recommendations; >0 = showing popular page N). Pull-to-refresh
  /// pages through popular books because the personalised endpoint
  /// returns the same list every time.
  int _popularPage = 0;

  /// The popular page currently displayed, or null while showing the
  /// personalised recommendations.
  List<DisplayBook>? _pagedBooks;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Check for updates after frame is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Drives the floating nav bar's hide-on-scroll: hide while scrolling
  /// down, show while scrolling up, always show at the very top. Only
  /// applies while the floating bar and hide-on-scroll are both on.
  void _onScroll() {
    final hideEnabled =
        ref.read(floatingNavProvider) && ref.read(hideNavOnScrollProvider);
    if (!hideEnabled) {
      _setNavVisible(true);
      return;
    }
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels <= 0) {
      _setNavVisible(true);
      return;
    }
    if (position.userScrollDirection == ScrollDirection.reverse) {
      _setNavVisible(false);
    } else if (position.userScrollDirection == ScrollDirection.forward) {
      _setNavVisible(true);
    }
  }

  void _setNavVisible(bool visible) {
    if (ref.read(navBarVisibleProvider) != visible) {
      ref.read(navBarVisibleProvider.notifier).state = visible;
    }
  }

  /// Scroll the recommendation grid back to the top (used by the
  /// Recommended nav destination).
  void scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    }
  }

  /// Pull-to-refresh: show the next page of popular books. The
  /// personalised endpoint returns the same list every time, so paging
  /// popular is the only way a refresh shows genuinely different books.
  Future<void> _refreshRecommendations() async {
    await _loadPopularPage(_popularPage + 1);
  }

  Future<void> _loadPopularPage(int page) async {
    final api = ref.read(zlibraryApiProvider);
    final res = await api.search(order: 'popular', page: page, limit: 20);
    if (!mounted) return;
    final books = res.data;
    final totalPages = res.meta?['total_pages'];
    final outOfRange = totalPages is int && page > totalPages;
    if (!res.success || books == null || books.isEmpty || outOfRange) {
      // No more pages (or the fetch failed) — wrap back to page 1.
      if (page != 1) {
        await _loadPopularPage(1);
        return;
      }
      // Page 1 itself failed: nothing to wrap to — say so instead of
      // silently leaving the old list in place (a failed first refresh
      // otherwise looks exactly like a refresh that never fired).
      if (mounted && (!res.success || books == null)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(AppLocalizations.of(context).get('refresh_failed')),
          ),
        );
      }
      return;
    }
    setState(() {
      _popularPage = page;
      _pagedBooks = books.map((b) => b.toDisplay()).toList();
    });
  }

  Future<void> _checkForUpdates() async {
    final hasUpdate = await UpdateService.checkForUpdate();

    if (!hasUpdate || !mounted) return;

    final locale = Localizations.localeOf(context).languageCode;
    final isZh = locale == 'zh';

    if (UpdateService.forceUpdate) {
      // Force update - non-dismissable dialog with download channels
      showUpdateDialog(context);
    } else if (!UpdateService.isVersionDismissed()) {
      // Normal update - show snackbar (non-intrusive)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.system_update, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isZh
                      ? '发现新版本 ${UpdateService.latestVersion}'
                      : 'New version ${UpdateService.latestVersion} available',
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: isZh ? '更新' : 'Update',
            textColor: Colors.white,
            onPressed: () => showUpdateDialog(context),
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 6),
          dismissDirection: DismissDirection.horizontal,
        ),
      );

      // Mark as shown (will show again next day)
      UpdateService.dismissUpdate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final blurEnabled = ref.watch(blurEnabledProvider);

    // The glass header floats over the recommendation grid so the grid
    // scrolls underneath it (visible through the blur). Its height is
    // fixed, so the grid reserves the same space on top. When the
    // line-unavailable banner is shown it takes the status-bar inset
    // itself, so the header adds none.
    final topInset =
        authState.lineUnavailable ? 0.0 : MediaQuery.of(context).padding.top;
    const searchBarHeight = 54.0;
    const headerPadding = 12.0;
    const greetingHeight = 58.0;
    const headerGap = 12.0;
    final headerHeight = topInset +
        headerPadding +
        searchBarHeight +
        headerGap +
        greetingHeight +
        headerPadding;
    // A little slack so the first row never tucks under the glass.
    final gridTopPadding = headerHeight + 8;

    // Header content (search bar + greeting). The blur is applied
    // around it only when the blur switch is on; otherwise the header
    // is a solid surface so nothing shows through.
    final header = Container(
      decoration: BoxDecoration(
        color: blurEnabled ? cs.surface.withValues(alpha: 0.65) : cs.surface,
        border: Border(
          bottom: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            24, topInset + headerPadding, 24, headerPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search Bar Trigger
            GestureDetector(
              onTap: () =>
                  Navigator.of(context).pushNamed(AppRoutes.search),
              child: Container(
                height: searchBarHeight,
                padding: const EdgeInsets.only(left: 20, right: 8),
                decoration: BoxDecoration(
                  color: cs.surface.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, color: cs.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context).get('search_for_books'),
                        style: TextStyle(
                          color:
                              cs.onSurfaceVariant.withValues(alpha: 0.7),
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.arrow_forward,
                          color: Colors.white, size: 20),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: headerGap),

            // Greeting (below the search bar)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getGreeting(context),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  user?.name ?? (isZh ? '读者' : 'Reader'),
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 28,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    // When paging popular books, show the fetched page instead of the
    // personalised recommendations.
    final booksAsync = ref.watch(homeRecommendedProvider);
    final effectiveAsync = (_popularPage > 0 && _pagedBooks != null)
        ? AsyncValue.data(_pagedBooks!)
        : booksAsync;

    return Column(
      children: [
        if (authState.lineUnavailable)
          _buildLineUnavailableBanner(context, isZh),
        Expanded(
          child: Stack(
            children: [
              _buildBookGrid(effectiveAsync, gridTopPadding),
              // ========== 悬浮毛玻璃头部 ==========
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: blurEnabled
                    ? ClipRect(
                        child: BackdropFilter(
                          filter:
                              ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                          child: header,
                        ),
                      )
                    : header,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLineUnavailableBanner(BuildContext context, bool isZh) {
    return Material(
      color: Colors.orange.shade50,
      child: InkWell(
        // DomainNotifier.setDomain handles reverify + cache invalidation
        // internally, so just opening the picker is enough.
        onTap: () => showDialog(
          context: context,
          builder: (_) => const DomainSelectionDialog(),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.cloud_off_outlined,
                    color: Colors.orange.shade800, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isZh ? '当前线路不可用' : 'Current line unavailable',
                        style: TextStyle(
                          color: Colors.orange.shade900,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        isZh
                            ? '已使用缓存登录信息，点此切换线路'
                            : 'Using cached login. Tap to switch line.',
                        style: TextStyle(
                          color: Colors.orange.shade800,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    color: Colors.orange.shade700, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // topPadding reserves the floating glass header's height inside the
  // scrollable, so the grid scrolls underneath the header (blurred)
  // instead of starting below it.
  Widget _buildBookGrid(
      AsyncValue<List<DisplayBook>> booksAsync, double topPadding) {
    return booksAsync.when(
      data: (books) {
        if (books.isEmpty) {
          return Padding(
            padding: EdgeInsets.fromLTRB(40, topPadding + 40, 40, 40),
            child: const EmptyState(
              icon: Icons.book_outlined,
              title: 'No books found',
            ),
          );
        }

        final itemCount = books.length;

        return LayoutBuilder(
          builder: (context, constraints) {
            const maxCardWidth = 220.0;
            const columnSpacing = 16.0;
            const horizontalPadding = 20.0;
            final gridWidth = (constraints.maxWidth - horizontalPadding * 2)
                .clamp(0.0, double.infinity);
            final columnCount = (gridWidth / (maxCardWidth + columnSpacing))
                .ceil()
                .clamp(1, double.infinity);
            final cardWidth =
                ((gridWidth - columnSpacing * (columnCount - 1)) / columnCount)
                    .clamp(0.0, double.infinity);

            return RefreshIndicator(
              onRefresh: _refreshRecommendations,
              color: Theme.of(context).colorScheme.primary,
              // The spinner must appear below the floating glass header,
              // not behind it (the header paints on top of the grid).
              edgeOffset: topPadding,
              child: GridView.builder(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(20, topPadding, 20, 96),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: maxCardWidth,
                  mainAxisExtent: BookCard.compactHeightFor(cardWidth),
                  crossAxisSpacing: columnSpacing,
                  mainAxisSpacing: 12,
                ),
                itemCount: itemCount,
                itemBuilder: (context, index) {
                  final book = books[index];
                  return BookCard(
                    book: book,
                    compact: true,
                    showSourceBadge: true,
                    onTap: () {
                      Navigator.of(context).pushNamed(
                        AppRoutes.bookDetail,
                        arguments: book.asZLibBook,
                      );
                    },
                  );
                },
              ),
            );
          },
        );
      },
      loading: () => Padding(
        padding: EdgeInsets.only(top: topPadding + 40, bottom: 40),
        child: const LoadingWidget(message: 'Loading trending books...'),
      ),
      error: (error, stack) => Padding(
        padding: EdgeInsets.fromLTRB(20, topPadding + 20, 20, 20),
        child: const EmptyState(
          icon: Icons.error_outline,
          title: 'Could not load books',
          message: 'Please check your connection',
        ),
      ),
    );
  }
}
