import 'package:olib_api_plugin/olib_api_plugin.dart';

/// 书详情页路由参数。新代码应使用这个；旧代码直接传 [Book] 也兼容。
/// 下载只走用户自己的 z站 账号。
class BookDetailArgs {
  final Book book;

  const BookDetailArgs({required this.book});
}
