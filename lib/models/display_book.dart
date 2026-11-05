import 'package:olib_api_plugin/olib_api_plugin.dart';

// Project imports:
import '../core/annas_archive.dart';

/// 数据源标识
enum BookSource { zlibrary, annasArchive }

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

  /// 是否来自 Anna's Archive
  bool get isAnnasArchive => source == BookSource.annasArchive;

  /// 获取原始 z站 Book 对象（仅当 source == zlibrary 时有效）
  Book? get asZLibBook => isZLibrary ? original as Book? : null;

  /// 获取原始 Anna's Archive BookData（仅当 source == annasArchive 时有效）
  BookData? get asAnnaBookData =>
      isAnnasArchive ? original as BookData? : null;

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

/// Anna's Archive BookData → DisplayBook.
///
/// id 是 md5（十六进制字符串，不再二次哈希）；详情页用它取 BookInfoData，
/// 下载（Stage 3）用它前 8 位十六进制转 int 作 DownloadTask 的键。
/// tag 是从 info 列解析出的格式标签（如 "EPUB"）；BookData 没有年份和
/// 评分，简介/出版社/文件大小只在详情页的 BookInfoData 里才有。
extension BookDataToDisplay on BookData {
  DisplayBook toDisplay() => DisplayBook(
    id: md5,
    title: title,
    author: author,
    cover: thumbnail,
    tag: ArchiveParsing.formatFromInfo(info),
    source: BookSource.annasArchive,
    original: this,
  );
}
