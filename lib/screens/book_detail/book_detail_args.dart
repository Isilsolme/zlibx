import 'package:olib_api_plugin/olib_api_plugin.dart';
import '../../models/display_book.dart';

/// 书详情页路由参数。新代码应使用这个；旧代码直接传 [Book] 也兼容。
/// 下载走用户自己的 z站 账号，或外部源的解析链接（Anna's Archive /
/// LibGen，见 external_download.dart）。
///
/// 两种形态，二选一：
/// * [book] — z站 vendor Book（旧调用方直接传 Book，或用本构造器）；
/// * [displayBook] — 统一展示模型（Anna's Archive / LibGen 从搜索页
///   直接传 DisplayBook；详情页按 DisplayBook.source 分支）。
class BookDetailArgs {
  final Book? book;
  final DisplayBook? displayBook;

  const BookDetailArgs({required this.book}) : displayBook = null;

  const BookDetailArgs.fromDisplayBook({required this.displayBook})
    : book = null;

  /// 是否 Anna's Archive 详情（按 DisplayBook.source 判断）。
  bool get isAnnasArchive => displayBook?.isAnnasArchive ?? false;

  /// 是否 LibGen 详情（按 DisplayBook.source 判断）。
  bool get isLibGen => displayBook?.isLibGen ?? false;
}
