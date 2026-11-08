import '../models/display_book.dart';

/// 书架来源
enum ShelfSource { library }

/// 统一书架条目 — z站收藏
class UnifiedShelfItem {
  final ShelfSource source;
  final DisplayBook displayBook;
  final String rawBookId;
  final int? lastReadTime;

  String get categoryKey => '${source.name}:$rawBookId';

  const UnifiedShelfItem({
    required this.source,
    required this.displayBook,
    required this.rawBookId,
    this.lastReadTime,
  });
}
