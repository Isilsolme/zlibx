import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';
import 'package:zlibx/providers/books_provider.dart';
import 'package:zlibx/providers/zlibrary_provider.dart';

/// [DownloadedBooksNotifier]（云端下载历史）回归测试。
///
/// 旧实现是一个只拉第 1 页（limit 100）、进程内只拉一次的
/// FutureProvider：超过 100 条后，更早的记录（其他设备下的书）永远
/// 留在第 2 页之后不出现，页面也没有任何刷新入口——"下载历史（云端）
/// 不能同步其他设备"。这里锁住修复后的行为：全量翻页、可靠终止、
/// 打开页面 / 下拉时的静默对账、失败时保留已有数据。
class _FakeZLibraryApi implements ZLibraryApi {
  _FakeZLibraryApi(this.pages, {this.totalPages});

  /// page -> 该页返回的书；缺页按空列表处理。
  final Map<int, List<Book>> pages;

  /// 随每页响应返回的 total_pages（null 表示响应不带 meta）。
  final int? totalPages;

  int calls = 0;
  final List<int?> seenPages = [];
  final List<int?> seenLimits = [];

  /// 置为 true 后所有请求都失败（模拟断网 / 被墙）。
  bool fail = false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unexpected: ${invocation.memberName}');

  @override
  Future<ApiResponse<List<Book>>> getUserDownloaded({
    int? page,
    int? limit,
  }) async {
    calls++;
    seenPages.add(page);
    seenLimits.add(limit);
    if (fail) {
      return ApiResponse.fail('boom', statusCode: 500);
    }
    return ApiResponse.ok(
      pages[page] ?? const [],
      meta: totalPages == null ? null : {'total_pages': totalPages},
    );
  }
}

Book _book(int id) => Book(id: id, title: 'Book $id');

ProviderContainer _container(_FakeZLibraryApi api) {
  final container = ProviderContainer(
    overrides: [zlibraryApiProvider.overrideWithValue(api)],
  );
  return container;
}

/// 等待 build() 触发的首次拉取落地（与 saved_books_first_load_test
/// 同一写法）。
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 100));

void main() {
  test('全量翻页：多页记录全部拉齐，顺序保持服务端顺序（新在前）', () async {
    final api = _FakeZLibraryApi(
      {
        1: [_book(3), _book(2)],
        2: [_book(1)],
        3: [_book(0)],
      },
      totalPages: 3,
    );
    final container = _container(api);
    addTearDown(container.dispose);

    container.read(downloadedBooksProvider);
    await _settle();

    final state = container.read(downloadedBooksProvider);
    expect(state.valueOrNull?.map((b) => b.id).toList(), [3, 2, 1, 0]);
    expect(api.calls, 3);
    expect(api.seenPages, [1, 2, 3]);
    expect(api.seenLimits, [100, 100, 100]);
  });

  test('缺 total_pages 时空页终止：拉到空页即停，不空转', () async {
    final api = _FakeZLibraryApi({
      1: [_book(1), _book(2)],
      2: [],
    });
    final container = _container(api);
    addTearDown(container.dispose);

    container.read(downloadedBooksProvider);
    await _settle();

    expect(container.read(downloadedBooksProvider).valueOrNull?.length, 2);
    expect(api.calls, 2);
  });

  test('服务端把 limit 压小 / 忽略 page（每页回同一批）时按"无新增"终止', () async {
    // 两页都回同一批书、不带 meta：镜像把 limit 压小或忽略 page 的
    // 兜底路径。旧逻辑没有翻页，这条锁住"不空转也不丢数据"。
    final api = _FakeZLibraryApi({
      1: [_book(1), _book(2)],
      2: [_book(1), _book(2)],
    });
    final container = _container(api);
    addTearDown(container.dispose);

    container.read(downloadedBooksProvider);
    await _settle();

    final state = container.read(downloadedBooksProvider);
    expect(state.valueOrNull?.map((b) => b.id).toList(), [1, 2]);
    expect(api.calls, 2);
  });

  test('静默对账：把其他设备新下的记录补进已有列表', () async {
    final api = _FakeZLibraryApi(
      {
        1: [_book(1)],
      },
      totalPages: 1,
    );
    final container = _container(api);
    addTearDown(container.dispose);

    container.read(downloadedBooksProvider);
    await _settle();
    expect(container.read(downloadedBooksProvider).valueOrNull?.length, 1);

    // 模拟"另一台设备刚下了一本书"：服务端列表变长，然后页面打开
    // / 下拉触发的 silent 对账把它补进来。
    api.pages[1] = [_book(2), _book(1)];
    await container
        .read(downloadedBooksProvider.notifier)
        .loadDownloadedBooks(silent: true);

    final state = container.read(downloadedBooksProvider);
    expect(state.valueOrNull?.map((b) => b.id).toList(), [2, 1]);
  });

  test('静默对账失败保留已有列表，不闪 error', () async {
    final api = _FakeZLibraryApi(
      {
        1: [_book(1)],
      },
      totalPages: 1,
    );
    final container = _container(api);
    addTearDown(container.dispose);

    container.read(downloadedBooksProvider);
    await _settle();
    expect(container.read(downloadedBooksProvider).valueOrNull?.length, 1);

    api.fail = true;
    await container
        .read(downloadedBooksProvider.notifier)
        .loadDownloadedBooks(silent: true);

    final state = container.read(downloadedBooksProvider);
    expect(state.valueOrNull?.map((b) => b.id).toList(), [1]);
  });

  test('首次拉取失败：报 error（可重试），不假装成空历史', () async {
    final api = _FakeZLibraryApi(const {})..fail = true;
    final container = _container(api);
    addTearDown(container.dispose);

    container.read(downloadedBooksProvider);
    await _settle();

    final state = container.read(downloadedBooksProvider);
    expect(state, isA<AsyncError>());
  });
}
