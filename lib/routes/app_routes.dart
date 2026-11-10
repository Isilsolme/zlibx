import 'package:flutter/material.dart';

import '../screens/account/account_screen.dart';
import '../screens/account/booklist_detail_screen.dart';
import '../screens/account/booklists_screen.dart';
import '../screens/account/my_comments_screen.dart';
import '../screens/account/user_profile_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/book_detail/book_detail_screen.dart';
import '../screens/comments/book_comments_screen.dart';
import '../screens/downloads/local_downloads_screen.dart';
import '../screens/favorites/favorites_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/reader/reader_screen.dart';
import '../screens/search/search_screen.dart';
import '../screens/settings/history_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/similar/similar_books_screen.dart';
import '../screens/splash/splash_screen.dart';

class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String home = '/home';
  static const String search = '/search';
  static const String bookDetail = '/book-detail';
  static const String favorites = '/favorites';
  static const String downloads = '/downloads';
  static const String history = '/history';
  static const String settings = '/settings';
  static const String similarBooks = '/similar-books';
  static const String bookComments = '/book-comments';
  static const String account = '/account';
  static const String booklists = '/booklists';
  static const String booklistDetail = '/booklist-detail';
  static const String myComments = '/my-comments';
  static const String userProfile = '/user-profile';
  static const String reader = '/reader';
}

/// The app's named-route table (passed to `MaterialApp.routes`).
///
/// Moved verbatim out of `_MyAppState.build` in `main.dart` so the table
/// can be asserted in a test (see `test/routes/app_routes_test.dart`).
Map<String, WidgetBuilder> buildAppRoutes() {
  return {
    AppRoutes.splash: (context) => const SplashScreen(),
    AppRoutes.login: (context) => const LoginScreen(),
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
      final args = ModalRoute.of(context)!.settings.arguments;
      // A missing/mistyped arguments object (deep link, hot-reload
      // route change) used to throw an async type-cast error and
      // red-screen. Show a plain fallback instead.
      if (args is BooklistDetailArgs) {
        return BooklistDetailScreen(args: args);
      }
      return const _MissingRouteArgsScreen();
    },
    AppRoutes.myComments: (context) => const MyCommentsScreen(),
    AppRoutes.userProfile: (context) => const UserProfileScreen(),
    AppRoutes.reader: (context) {
      final args = ModalRoute.of(context)!.settings.arguments;
      if (args is ReaderArgs) {
        return ReaderScreen(
          url: args.url,
          title: args.title,
          remixUserId: args.remixUserId,
          remixUserKey: args.remixUserKey,
        );
      }
      return const _MissingRouteArgsScreen();
    },
  };
}

/// Plain fallback for routes whose typed arguments are missing or of the
/// wrong type — see the booklistDetail / reader builders above.
class _MissingRouteArgsScreen extends StatelessWidget {
  const _MissingRouteArgsScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: const Center(child: Text('Page unavailable')),
    );
  }
}

/// Arguments for the user profile page. The id drives the comments
/// fetch; name/avatar come from the tapped comment itself (the
/// comments endpoint carries no profile header). [userHash] is the
/// profile hash from the comment's `user.hash` — it drives the
/// booklists fetch (`/profile/{userId}/{hash}`); null when the
/// comment did not carry one, in which case the page shows comments
/// only. Kept here, next to the route, because the comments screen
/// (avatar tap) and the profile screen (row tap-through) navigate to
/// each other — a screen-local class would make those two files
/// import each other.
class UserProfileArgs {
  final int userId;
  final String userName;
  final String userAvatar;
  final String? userHash;

  const UserProfileArgs({
    required this.userId,
    required this.userName,
    required this.userAvatar,
    this.userHash,
  });
}
