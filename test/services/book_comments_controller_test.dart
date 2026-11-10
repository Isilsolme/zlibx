import 'package:flutter_test/flutter_test.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';
import 'package:zlibx/screens/comments/controllers/book_comments_controller.dart';

/// [BookCommentsController.deleteComment] 的行为测试：乐观移除、失败
/// 放回原位、回复数同步、重复删除只调一次接口。
///
/// fake 只实现 controller 用到的两个方法，其余调用一律抛错。
class _FakeZLibraryApi implements ZLibraryApi {
  _FakeZLibraryApi({
    this.failDeleteIds = const {},
    this.deleteDelay,
  });

  final Set<int> failDeleteIds;
  final Duration? deleteDelay;

  final List<int> deletedIds = [];
  int deleteCalls = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unexpected: ${invocation.memberName}');

  @override
  Future<ApiResponse<BookCommentsPage>> getBookComments(
    String bookId, {
    int page = 0,
    int limit = 50,
  }) async {
    return ApiResponse.ok(
      BookCommentsPage(comments: _seedComments()),
    );
  }

  @override
  Future<ApiResponse<bool>> deleteBookComment(int commentId) async {
    deleteCalls++;
    deletedIds.add(commentId);
    if (deleteDelay != null) await Future<void>.delayed(deleteDelay!);
    if (failDeleteIds.contains(commentId)) {
      return ApiResponse.fail('delete failed');
    }
    return ApiResponse.ok(true);
  }
}

BookComment _comment({
  required int id,
  int? parentId,
  bool isCurrentUser = true,
}) {
  return BookComment(
    id: id,
    parentId: parentId,
    userId: isCurrentUser ? 7 : 8,
    text: 'comment $id',
    date: '2026-11-09 15:00:00',
    userName: isCurrentUser ? 'me' : 'other',
    userAvatar: '',
    dateRelative: '',
    isCurrentUser: isCurrentUser,
  );
}

/// 种子数据：一条自己的顶层评论（id 1）+ 一条别人回它的回复
/// （id 2），再加一条别人的顶层评论（id 3）。
List<BookComment> _seedComments() => [
      _comment(id: 1),
      _comment(id: 2, parentId: 1, isCurrentUser: false),
      _comment(id: 3, isCurrentUser: false),
    ];

Future<BookCommentsController> _loadedController(
  _FakeZLibraryApi api, {
  void Function(String message)? onNotice,
}) async {
  final notices = <String>[];
  final controller = BookCommentsController(
    bookId: 6134915,
    api: api,
    commentFailed: 'comment_failed',
    likeFailed: 'like_failed',
    commentDeleteFailed: 'comment_delete_failed',
    onNotice: (message) {
      notices.add(message);
      onNotice?.call(message);
    },
  );
  await controller.loadFirst(signedIn: true);
  return controller;
}

void main() {
  test('删除自己的顶层评论：列表移除，只调一次接口', () async {
    final api = _FakeZLibraryApi();
    final controller = await _loadedController(api);

    // 种子 [1, 2, 3] 经 orderCommentsNewestFirst 后是 [3, 1, 2]
    //（线程倒序：3 的线程在前，1 及其回复在后）。
    expect(controller.comments.map((c) => c.id).toList(), [3, 1, 2]);

    await controller.deleteComment(controller.comments.firstWhere(
      (c) => c.id == 1,
    ));

    expect(controller.comments.map((c) => c.id).toList(), [3, 2]);
    expect(api.deletedIds, [1]);
    expect(api.deleteCalls, 1);
  });

  test('删除回复：父评论的回复数减一', () async {
    final api = _FakeZLibraryApi();
    final controller = await _loadedController(api);

    expect(controller.replyCounts[1], 1);

    await controller.deleteComment(controller.comments.firstWhere(
      (c) => c.id == 2,
    ));

    expect(controller.comments.map((c) => c.id).toList(), [3, 1]);
    expect(controller.replyCounts[1], 0);
    expect(api.deletedIds, [2]);
  });

  test('删除失败：评论放回原位并提示', () async {
    final api = _FakeZLibraryApi(failDeleteIds: {1});
    final notices = <String>[];
    final controller = await _loadedController(
      api,
      onNotice: notices.add,
    );

    await controller.deleteComment(controller.comments.firstWhere(
      (c) => c.id == 1,
    ));

    expect(controller.comments.map((c) => c.id).toList(), [3, 1, 2]);
    expect(notices, ['comment_delete_failed']);
  });

  test('删除回复失败：父评论的回复数恢复', () async {
    final api = _FakeZLibraryApi(failDeleteIds: {2});
    final controller = await _loadedController(api);

    await controller.deleteComment(controller.comments.firstWhere(
      (c) => c.id == 2,
    ));

    expect(controller.comments.map((c) => c.id).toList(), [3, 1, 2]);
    expect(controller.replyCounts[1], 1);
  });

  test('重复删除：第二次直接返回，只调一次接口', () async {
    final api = _FakeZLibraryApi(
      deleteDelay: const Duration(milliseconds: 50),
    );
    final controller = await _loadedController(api);
    final target = controller.comments.firstWhere((c) => c.id == 1);

    final first = controller.deleteComment(target);
    final second = controller.deleteComment(target);
    await Future.wait([first, second]);

    expect(api.deleteCalls, 1);
    expect(controller.comments.map((c) => c.id).toList(), [3, 2]);
  });
}
