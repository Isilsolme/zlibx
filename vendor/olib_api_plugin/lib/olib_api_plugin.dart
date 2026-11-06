/// Z-Library API client + data models.
///
/// This is a clean-room rewrite built from the call sites in olib-mobile
/// (see README.md for the endpoint verification status of each method).
/// It intentionally exports only what the app imports:
/// [ZLibraryApi], [Book], [User] and [ApiResponse].
library;

export 'src/api_response.dart';
export 'src/book.dart';
export 'src/book_comment.dart';
export 'src/user.dart';
export 'src/zlibrary_api.dart';
