import 'package:olib_api_plugin/olib_api_plugin.dart';

/// 数据源标识
enum BookSource { zlibrary }

/// 统一书籍展示模型
///
/// 解耦 UI 组件（BookCard / BookListTile / BookHeroSection）与具体数据源。
/// 通过 [Book.toDisplay] extension 方法创建。
class DisplayBook {
  final String id;
  final String title;
  final String? author;
  final String? cover;

  /// 卡片左上标签（z站: 格式 "EPUB"）
  final String? tag;

  /// 卡片顶部辅助标签（z站: 年份）
  final String? tagExtra;

  /// 评分/兴趣分（z站: interestScore）
  final String? score;

  /// 卡片底部右侧辅助文本（z站=文件大小）
  final String? meta;

  /// 详情页简介
  final String? description;

  /// 出版社
  final String? publisher;

  /// 数据来源
  final BookSource source;

  /// 原始对象引用 — 用于路由传参等类型特定操作
  final dynamic original;

  const DisplayBook({
    required this.id,
    required this.title,
    this.author,
    this.cover,
    this.tag,
    this.tagExtra,
    this.score,
    this.meta,
    this.description,
    this.publisher,
    required this.source,
    this.original,
  });

  /// 是否来自 z站
  bool get isZLibrary => source == BookSource.zlibrary;

  /// 获取原始 z站 Book 对象（仅当 source == zlibrary 时有效）
  Book? get asZLibBook => isZLibrary ? original as Book? : null;

}

// ═══════════════════════════════════════════════════════════════════
// Extension 适配器
// ═══════════════════════════════════════════════════════════════════

/// z站 Book → DisplayBook
extension BookToDisplay on Book {
  DisplayBook toDisplay() => DisplayBook(
    id: id.toString(),
    title: title,
    author: author,
    cover: cover,
    tag: extension != null && extension!.isNotEmpty
        ? extension!.toUpperCase()
        : null,
    tagExtra: (year != null && year != 0) ? '$year' : null,
    score: interestScore,
    meta: filesizeString,
    description: description,
    publisher: publisher,
    source: BookSource.zlibrary,
    original: this,
  );
}
