import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';
import '../models/display_book.dart';
import '../models/unified_shelf_item.dart';
import 'books_provider.dart';

/// 书架来源筛选状态
class ShelfFilterNotifier extends Notifier<ShelfSource?> {
  @override
  ShelfSource? build() => null;

  void setFilter(ShelfSource? value) => state = value;
}

final shelfFilterProvider =
    NotifierProvider<ShelfFilterNotifier, ShelfSource?>(ShelfFilterNotifier.new);

/// 统一书架 — z站收藏
final unifiedShelfProvider = Provider<AsyncValue<List<UnifiedShelfItem>>>((
  ref,
) {
  final zlibAsync = ref.watch(savedBooksProvider);

  if (zlibAsync is AsyncLoading) {
    return const AsyncValue.loading();
  }

  final items = <UnifiedShelfItem>[];

  final zlibData = zlibAsync.valueOrNull;
  if (zlibData != null) {
    items.addAll(zlibData.map((b) => _fromZLib(b)));
  }

  return AsyncValue.data(items);
});

UnifiedShelfItem _fromZLib(Book book) {
  return UnifiedShelfItem(
    source: ShelfSource.library,
    displayBook: book.toDisplay(),
    rawBookId: book.id.toString(),
    lastReadTime: null,
  );
}
