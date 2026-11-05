import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/books_provider.dart';
import '../../providers/auth_provider.dart';
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

  // Only the home tab lives in the stack; bookshelf/downloads/settings
  // are pushed as routes, and search is opened from the home search box
  // (no nav tab).
  final List<Widget> _screens = [
    const _HomeTab(),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: _screens[_selectedIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha:0.05),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          elevation: 0,
          backgroundColor: cs.surface,
          onDestinationSelected: (index) {
            if (index == 1) {
              Navigator.of(context).pushNamed(AppRoutes.favorites);
            } else if (index == 2) {
              Navigator.of(context).pushNamed(AppRoutes.downloads);
            } else if (index == 3) {
              Navigator.of(context).pushNamed(AppRoutes.settings);
            } else {
              setState(() => _selectedIndex = index);
            }
          },
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home),
              label: AppLocalizations.of(context).get('home'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.library_books_outlined),
              selectedIcon: const Icon(Icons.library_books),
              label: AppLocalizations.of(context).get('bookshelf'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.cloud_download_outlined),
              selectedIcon: const Icon(Icons.cloud_download),
              label: AppLocalizations.of(context).get('downloads'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(Icons.settings),
              label: AppLocalizations.of(context).get('settings'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeTab extends ConsumerStatefulWidget {
  const _HomeTab();

  @override
  ConsumerState<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<_HomeTab> {
  @override
  void initState() {
    super.initState();
    // Check for updates after frame is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
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
    final cs = Theme.of(context).colorScheme;
    final isZh = Localizations.localeOf(context).languageCode == 'zh';

    // The glass header floats over the recommendation grid so the grid
    // scrolls underneath it (visible through the blur). Its height is
    // fixed, so the grid reserves the same space on top. When the
    // line-unavailable banner is shown it takes the status-bar inset
    // itself, so the header adds none.
    final topInset =
        authState.lineUnavailable ? 0.0 : MediaQuery.of(context).padding.top;
    const searchBarHeight = 54.0;
    const headerPadding = 12.0;
    const titleHeight = 22.0;
    const headerGap = 12.0;
    final headerHeight = topInset +
        headerPadding +
        searchBarHeight +
        headerGap +
        titleHeight +
        headerPadding;
    // A little slack so the first row never tucks under the glass.
    final gridTopPadding = headerHeight + 8;

    return Column(
      children: [
        if (authState.lineUnavailable)
          _buildLineUnavailableBanner(context, isZh),
        Expanded(
          child: Stack(
            children: [
              _buildBookGrid(
                  ref.watch(homeRecommendedProvider), gridTopPadding),
              // ========== 悬浮毛玻璃头部 ==========
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.surface.withValues(alpha: 0.65),
                        border: Border(
                          bottom: BorderSide(
                            color:
                                cs.outlineVariant.withValues(alpha: 0.4),
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
                              onTap: () => Navigator.of(context)
                                  .pushNamed(AppRoutes.search),
                              child: Container(
                                height: searchBarHeight,
                                padding:
                                    const EdgeInsets.only(left: 20, right: 8),
                                decoration: BoxDecoration(
                                  color: cs.surface.withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(30),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black
                                          .withValues(alpha: 0.06),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.search,
                                        color: cs.onSurfaceVariant),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        AppLocalizations.of(context)
                                            .get('search_for_books'),
                                        style: TextStyle(
                                          color: cs.onSurfaceVariant
                                              .withValues(alpha: 0.7),
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: cs.primary,
                                        borderRadius:
                                            BorderRadius.circular(20),
                                      ),
                                      child: const Icon(Icons.arrow_forward,
                                          color: Colors.white, size: 20),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: headerGap),

                            // 推荐书籍标题
                            Row(
                              children: [
                                Icon(Icons.local_fire_department_rounded,
                                    color: cs.primary, size: 22),
                                const SizedBox(width: 6),
                                Text(
                                  isZh ? '为你推荐' : 'Recommended',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: cs.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
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

            return GridView.builder(
              padding: EdgeInsets.fromLTRB(20, topPadding, 20, 32),
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
