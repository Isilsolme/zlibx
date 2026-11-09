import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';
import 'package:zlibx/providers/books_provider.dart';
import 'package:zlibx/providers/zlibrary_provider.dart';

/// [SavedBooksNotifier] 冷启动回归测试。
///
/// 根因（2026-11-09，今晚那批 §6(6) 引入）：`loadSavedBooks` 开头的
/// `state.valueOrNull` 在 `build()` 同步触发的路径里读 state，而首次
/// build 时 state 还不存在，Riverpod 会抛 StateError（'Tried to read
/// the state of an uninitialized provider'），抛在 try 之前、第一个
/// await 之前——拉取直接夭折，provider 永远卡在 loading，图书馆无限
/// 转圈。切账号调 `ref.invalidate` 后 build() 在已初始化的实例上重
/// 跑，state 可读，于是正常拉取。
///
/// 本文件第一个测试复现冷启动路径：全新容器里第一次 watch，不经过
/// 任何 invalidate，断言最终拿到 data。旧代码上它会失败（一直
/// loading，外加一个未接的 StateError）；修法后通过。
///
/// fake 只实现本测试用到的一个方法，其余调用一律抛错。
class _FakeZLibraryApi implements ZLibraryApi {
  int getUserSavedCalls = 0;
  int? lastPage;
  int? lastLimit;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unexpected: ${invocation.memberName}');

  @override
  Future<ApiResponse<List<Book>>> getUserSaved({int? page, int? limit}) async {
    getUserSavedCalls++;
    lastPage = page;
    lastLimit = limit;
    return ApiResponse.ok(
      const [Book(id: 1, title: 'Book 1'), Book(id: 2, title: 'Book 2')],
      meta: const {'total_pages': 1},
    );
  }
}

void main() {
  test('冷启动：第一次 watch 就拉到列表，不是一直 loading', () async {
    final api = _FakeZLibraryApi();
    final container = ProviderContainer(
      overrides: [zlibraryApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    // 第一次 read 即冷启动：build() 同步调 loadSavedBooks()，此时还
    // 没有任何旧 state。
    final firstRead = container.read(savedBooksProvider);
    expect(firstRead is AsyncLoading, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 100));

    final state = container.read(savedBooksProvider);
    expect(state.valueOrNull?.map((book) => book.id).toList(), [1, 2]);
    expect(api.getUserSavedCalls, 1);
    expect(api.lastPage, 1);
    expect(api.lastLimit, 100);
  });

  test('切账号：invalidate 后重新 build，照样拉到列表', () async {
    final api = _FakeZLibraryApi();
    final container = ProviderContainer(
      overrides: [zlibraryApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    container.read(savedBooksProvider);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(
      container.read(savedBooksProvider).valueOrNull?.length,
      2,
    );

    // 模拟切账号：invalidate 让 build() 在已初始化的实例上重跑。
    // 注意：没有监听器时 invalidate 不会立即重建，要等下一次 read
    // 才触发 build()；所以先 read 触发重建，再等拉取完成。
    container.invalidate(savedBooksProvider);
    container.read(savedBooksProvider);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final state = container.read(savedBooksProvider);
    expect(state.valueOrNull?.map((book) => book.id).toList(), [1, 2]);
    expect(api.getUserSavedCalls, 2);
  });
}
