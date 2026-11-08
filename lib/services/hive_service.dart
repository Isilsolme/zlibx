import 'package:hive_flutter/hive_flutter.dart';

class HiveService {
  static const String settingsBoxName = 'settings';
  static const String authBoxName = 'auth';
  static const String booklistHtmlBoxName = 'booklist_html';

  static Future<void> init() async {
    await Hive.initFlutter();
    // 三个 box 互不依赖，并行打开（此前串行，启动链路多等两轮
    // 磁盘 IO）。
    await Future.wait([
      Hive.openBox(settingsBoxName),
      Hive.openBox(authBoxName),
      Hive.openBox(booklistHtmlBoxName),
    ]);
  }

  static Box get settingsBox => Hive.box(settingsBoxName);
  static Box get authBox => Hive.box(authBoxName);
  static Box get booklistHtmlBox => Hive.box(booklistHtmlBoxName);
}
