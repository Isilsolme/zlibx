import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/zlibrary_provider.dart';
import 'routes/app_routes.dart';
import 'screens/splash/splash_screen.dart';
import 'screens/auth/login_screen.dart';
// import 'screens/auth/register_screen.dart'; // Registration disabled - API不支持
import 'screens/home/home_screen.dart';
import 'screens/search/search_screen.dart';
import 'screens/book_detail/book_detail_screen.dart';
import 'screens/favorites/favorites_screen.dart';
import 'screens/settings/history_screen.dart';
import 'screens/downloads/local_downloads_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/similar/similar_books_screen.dart';
import 'screens/comments/book_comments_screen.dart';
import 'screens/account/account_screen.dart';
import 'screens/account/booklists_screen.dart';
import 'screens/account/booklist_detail_screen.dart';
import 'screens/account/my_comments_screen.dart';
import 'screens/account/user_profile_screen.dart';
import 'screens/reader/reader_screen.dart';
import 'services/hive_service.dart';
import 'services/booklist_html_cache.dart';
import 'services/booklist_share_codec.dart';
import 'services/share_intent_handler.dart';
import 'services/instance_manager.dart';
import 'services/challenge_html_cache.dart';
import 'services/webview_challenge_solver.dart';
import 'screens/challenge_solver/challenge_solver_screen.dart';
import 'l10n/app_localizations.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HiveService.init();

  // Warm the Anna's Archive / LibGen mirror catalogue (open-slum.org) so
  // the first external search does not wait on it. refreshOnStartup is
  // the startup variant of InstanceManager.refresh(): it restores the
  // cached list first and never throws. Fire-and-forget on purpose —
  // startup must not block on the mirror list.
  unawaited(InstanceManager().refreshOnStartup());

  // When the headless challenge solve fails (e.g. a human CAPTCHA shows),
  // show the solver as a visible page over the current screen. The user
  // watches the check clear and the page closes itself as soon as the
  // HTML is captured; the caller then parses the cached HTML instead of
  // retrying a doomed Dio request. Registered here (before runApp) so it
  // is in place before any Anna search can run; the callback only uses
  // rootNavigatorKey when it is actually invoked.
  WebviewChallengeSolver.visibleSolverFallback = (url) async {
    final context = rootNavigatorKey.currentContext;
    if (context == null) return null;
    final solved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
          builder: (_) => ChallengeSolverScreen(url: url)),
    );
    return solved == true ? ChallengeHtmlCache.get(url) : null;
  };

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  @override
  void initState() {
    super.initState();
    // Fire-and-forget: start listening for shared booklists.
    ref.read(shareIntentHandlerProvider).start();

    // The plugin reports the raw HTML of every booklist page it
    // loads over Dio; persist it so the next open paints from cache
    // first (see BooklistHtmlCache). Registered once here: the
    // provider hands out one shared ZLibraryApi instance.
    // Account-scoped pages (own lists, detail pages) are stored
    // under the current account's partition, matching the keys the
    // screens read; public pages keep the plain URL key.
    ref.read(zlibraryApiProvider).onBooklistHtmlLoaded = (url, html) {
      final accountId = BooklistHtmlCache.isPrivateUrl(url)
          ? (ref.read(authProvider).user?.id ?? 'signed-out')
          : null;
      BooklistHtmlCache.store(url, html, accountId: accountId);
    };
  }

  @override
  Widget build(BuildContext context) {
    final themeModeState = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    // When a shared booklist arrives while we're elsewhere in the app,
    // jump to favorites — that screen consumes the pending data.
    ref.listen<BooklistShareData?>(pendingBooklistImportProvider,
        (prev, next) {
      if (next == null) return;
      final nav = rootNavigatorKey.currentState;
      if (nav == null) return;
      nav.pushNamedAndRemoveUntil(AppRoutes.favorites, (r) => r.isFirst);
    });
    
    // Convert AppThemeMode to ThemeMode
    ThemeMode themeMode;
    switch (themeModeState) {
      case AppThemeMode.light:
        themeMode = ThemeMode.light;
      case AppThemeMode.dark:
        themeMode = ThemeMode.dark;
      case AppThemeMode.system:
        themeMode = ThemeMode.system;
    }

    // Material You dynamic color (Android 12+): the ColorScheme comes from
    // the wallpaper; where dynamic color is unavailable the schemes are
    // null and AppTheme falls back to the built-in palette.
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return MaterialApp(
          navigatorKey: rootNavigatorKey,
          title: 'zlibx',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightThemeFromScheme(lightDynamic),
          darkTheme: AppTheme.darkThemeFromScheme(darkDynamic),
          themeMode: themeMode,

          // Localization
          locale: locale,
          supportedLocales: supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],

          initialRoute: AppRoutes.splash,
          routes: {
            AppRoutes.splash: (context) => const SplashScreen(),
            AppRoutes.login: (context) => const LoginScreen(),
            // AppRoutes.register: (context) => const RegisterScreen(), // Disabled
            AppRoutes.home: (context) => const HomeScreen(),
            AppRoutes.search: (context) => const SearchScreen(),
            AppRoutes.bookDetail: (context) => const BookDetailScreen(),
            AppRoutes.favorites: (context) => const FavoritesScreen(),
            AppRoutes.history: (context) => const HistoryScreen(),
            AppRoutes.downloads: (context) => const LocalDownloadsScreen(),
            AppRoutes.settings: (context) => const SettingsScreen(),
            AppRoutes.similarBooks: (context) => const SimilarBooksScreen(),
            AppRoutes.bookComments: (context) => const BookCommentsScreen(),
            AppRoutes.account: (context) => const AccountScreen(),
            AppRoutes.booklists: (context) => const BooklistsScreen(),
            AppRoutes.booklistDetail: (context) {
              final args = ModalRoute.of(context)!.settings.arguments
                  as BooklistDetailArgs;
              return BooklistDetailScreen(args: args);
            },
            AppRoutes.myComments: (context) => const MyCommentsScreen(),
            AppRoutes.userProfile: (context) => const UserProfileScreen(),
            AppRoutes.reader: (context) {
              final args =
                  ModalRoute.of(context)!.settings.arguments as ReaderArgs;
              return ReaderScreen(
                url: args.url,
                title: args.title,
                remixUserId: args.remixUserId,
                remixUserKey: args.remixUserKey,
              );
            },
          },
        );
      },
    );
  }
}
