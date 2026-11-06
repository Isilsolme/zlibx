import 'package:hive_flutter/hive_flutter.dart';

class HiveService {
  static const String settingsBoxName = 'settings';
  static const String authBoxName = 'auth';

  /// Reading positions for the built-in EPUB reader: keyed by
  /// `book_<id>` (or the file path when the book has no id), value is
  /// `{'cfi': <start CFI>, 'locations': <[String]>}`.
  static const String epubPositionsBoxName = 'epub_positions';

  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(settingsBoxName);
    await Hive.openBox(authBoxName);
    await Hive.openBox(epubPositionsBoxName);
  }

  static Box get settingsBox => Hive.box(settingsBoxName);
  static Box get authBox => Hive.box(authBoxName);
  static Box get epubPositionsBox => Hive.box(epubPositionsBoxName);
}
