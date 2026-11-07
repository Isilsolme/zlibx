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
