import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/zlibrary_provider.dart';
import '../../routes/app_routes.dart';
import '../../screens/comments/book_comments_screen.dart';
import '../../screens/comments/widgets/comment_avatar.dart';
import '../../screens/comments/widgets/comment_metric_chip.dart';
import '../../screens/book_detail/book_detail_args.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/gradient_app_bar.dart';
import '../../widgets/loading_widget.dart';
import 'comment_book_ref.dart';

/// One comment the signed-in user posted, as shown on the website's
/// profile "Comments" tab: which book it was on, the text, when, and
/// how many likes it has.
class MyComment {
  final int bookId;
  final String bookTitle;
  final String text;
  final String date;
  final int likeCount;
  final int userId;
  final String userAvatar;
  final String userHash;

  const MyComment({
    required this.bookId,
    required this.bookTitle,
    required this.text,
    required this.date,
    this.likeCount = 0,
    required this.userId,
    this.userAvatar = '',
    this.userHash = '',
  });
}

/// "My Comments": the signed-in user's own posted comments, the same
/// collection the website shows on the profile Comments tab
/// (`GET /papi/comments/user/{userId}/{page}?limit=500`, confirmed by a
/// packet capture on 2026-11-06). Tapping a comment opens that book's
/// comments page; tapping the book-title row (cover thumbnail + title)
/// opens the book's detail page (the user-comments API carries no book
/// hash, so it is resolved by a title search first — see
/// [_MyCommentsScreenState._openBookDetail]).
/// Deleting is not implemented (delete endpoint unknown).
class MyCommentsScreen extends ConsumerStatefulWidget {
  const MyCommentsScreen({super.key});

  @override
  ConsumerState<MyCommentsScreen> createState() => _MyCommentsScreenState();
}

class _MyCommentsScreenState extends ConsumerState<MyCommentsScreen> {
  List<MyComment> _comments = [];
  bool _isLoading = true;
  bool _loggedIn = true;

  /// 正在解析书 hash 并准备跳详情的 bookId：书名行尾转圈，防重复点击。
  final Set<int> _openingBookIds = {};

  /// bookId → 标题搜索反查结果（hash + 封面）。加载后逐本后台串行
  /// 预取，每解析完一本就刷新对应书名行的封面；跳详情优先用缓存。
  final Map<int, CommentBookRef> _bookRefs = {};

  /// 预取上限：评论一次最多拉 500 条，逐本搜索会放大请求量，只预取
  /// 前 [_kMaxBookPrefetch] 本（足够铺满几屏）；未预取到的行显示
  /// 占位图，点按时仍会解析并跳转。
  static const int _kMaxBookPrefetch = 10;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (ref.read(authProvider).user == null) {
      setState(() {
        _loggedIn = false;
        _isLoading = false;
      });
      return;
    }
    setState(() => _isLoading = true);
    final api = ref.read(zlibraryApiProvider);
    List<MyComment> comments = const [];
    try {
      final response = await api.getMyComments();
      if (response.success && response.data != null) {
        comments = response.data!.entries
            .map((e) => MyComment(
                  bookId: e.bookId,
                  bookTitle: e.bookTitle,
                  text: e.comment.text,
                  date: e.comment.dateRelative.isNotEmpty
                      ? e.comment.dateRelative
                      : e.comment.date,
                  likeCount: e.comment.likeCount,
                  userId: e.comment.userId,
                  userAvatar: e.comment.userAvatar,
                  userHash: e.comment.userHash,
                ))
            .toList();
      }
    } catch (error) {
      // 失败按空列表处理，下拉重试
      debugPrint('[my_comments] ignored ${error.runtimeType}');
    }
    if (!mounted) return;
    setState(() {
      _comments = comments;
      _isLoading = false;
    });
    unawaited(_prefetchBookRefs());
  }

  /// 逐本预取书名行的 hash + 封面（串行，避免并发风暴）。同一
  /// bookId 只搜一次；已解析过的跳过；页面销毁即停；单本失败不
  /// 阻塞其余（保持占位图，点按时再试）。
  Future<void> _prefetchBookRefs() async {
    final api = ref.read(zlibraryApiProvider);
    final seen = <int>{};
    var attempts = 0;
    for (final comment in _comments) {
      if (!mounted || attempts >= _kMaxBookPrefetch) return;
      final id = comment.bookId;
      if (id <= 0 || !seen.add(id)) continue;
      if (_bookRefs[id]?.hasHash ?? false) continue;
      attempts++;
      try {
        final info =
            await resolveCommentBookRef(api, id, comment.bookTitle);
        if (!mounted || info == null) continue;
        setState(() => _bookRefs[id] = info);
      } catch (error) {
        // 单本失败保持占位图，点按时重试。
        debugPrint('[my_comments] prefetch ignored ${error.runtimeType}');
      }
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // --------------------------------------------------------------- 导航

  void _openComments(MyComment comment) {
    Navigator.of(context).pushNamed(
      AppRoutes.bookComments,
      arguments: BookCommentsArgs(
        bookId: comment.bookId,
        bookTitle: comment.bookTitle,
      ),
    );
  }

  void _openProfile(MyComment comment) {
    final userName = ref.read(authProvider).user?.name ?? '';
    Navigator.of(context).pushNamed(
      AppRoutes.userProfile,
      arguments: UserProfileArgs(
        userId: comment.userId,
        userName: userName,
        userAvatar: comment.userAvatar,
        userHash: comment.userHash,
      ),
    );
  }

  /// 书名行 → 书籍详情。用户评论接口只给 bookId + 书名，没有书 hash；
  /// 详情页靠 hash 拉全量数据，所以先用标题搜索反查同 id 书目的
  /// eapi hash（[resolveCommentBookRef]，顺带取回封面），再带最小
  /// [Book] 进详情页，由 `bookDetailsProvider` 拉取完整信息。
  /// 预取缓存里有 hash 就不再搜索。
  ///
  /// 解析中该书名行尾转圈；失败提示且不跳转（不进残缺详情页）。
  Future<void> _openBookDetail(MyComment comment) async {
    if (comment.bookId <= 0 || _openingBookIds.contains(comment.bookId)) {
      return;
    }
    setState(() => _openingBookIds.add(comment.bookId));
    try {
      var hash = _bookRefs[comment.bookId]?.hash ?? '';
      if (hash.isEmpty) {
        final api = ref.read(zlibraryApiProvider);
        final info = await resolveCommentBookRef(
          api,
          comment.bookId,
          comment.bookTitle,
        );
        if (!mounted) return;
        if (info != null) {
          setState(() => _bookRefs[comment.bookId] = info);
          hash = info.hash;
        }
      }
      if (!mounted) return;
      if (hash.isEmpty) {
        _showSnack(AppLocalizations.of(context).get('open_book_failed'));
        return;
      }
      Navigator.of(context).pushNamed(
        AppRoutes.bookDetail,
        arguments: BookDetailArgs(
          book: Book(
            id: comment.bookId,
            title: comment.bookTitle,
            hash: hash,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      debugPrint('[my_comments] open detail ignored ${error.runtimeType}');
      _showSnack(AppLocalizations.of(context).get('open_book_failed'));
    } finally {
      if (mounted) {
        setState(() => _openingBookIds.remove(comment.bookId));
      } else {
        _openingBookIds.remove(comment.bookId);
      }
    }
  }

  // --------------------------------------------------------------- 构建

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    Widget body;
    if (_isLoading) {
      body = LoadingWidget(message: l10n.get('loading'));
    } else if (!_loggedIn) {
      body = EmptyState(
        icon: Icons.login_rounded,
        title: l10n.get('login_to_view_comments'),
        action: FilledButton(
          onPressed: () => Navigator.of(context).pushNamed(AppRoutes.login),
          child: Text(l10n.get('login')),
        ),
      );
    } else if (_comments.isEmpty) {
      body = EmptyState(
        icon: Icons.comment_outlined,
        title: l10n.get('no_comments'),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
          itemCount: _comments.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final comment = _comments[index];
            final userName = ref.read(authProvider).user?.name ?? '';
            return _MyCommentCard(
              comment: comment,
              userName: userName,
              coverUrl: _bookRefs[comment.bookId]?.cover ?? '',
              isOpeningBook: _openingBookIds.contains(comment.bookId),
              onCardTap: () => _openComments(comment),
              onBookTap: () => _openBookDetail(comment),
              onAvatarTap: () => _openProfile(comment),
            );
          },
        ),
      );
    }

    return Scaffold(
      appBar: GradientAppBar(title: l10n.get('my_comments')),
      body: body,
    );
  }
}

/// 卡片化的一条“我的评论”，与书籍评论区同一套视觉语言：
/// 书名行（封面缩略图 + 书名，点击 → 书籍详情）+ 头像/昵称/正文/
/// 日期与点赞数。点卡片其余区域进入该书的评论区。
class _MyCommentCard extends StatelessWidget {
  final MyComment comment;
  final String userName;

  /// 书名行的封面 URL；空串显示占位图（hash/封面未解析到）。
  final String coverUrl;

  /// 书 hash 解析中：书名行尾显示转圈并禁止再次点击。
  final bool isOpeningBook;
  final VoidCallback onCardTap;
  final VoidCallback onBookTap;
  final VoidCallback onAvatarTap;

  const _MyCommentCard({
    required this.comment,
    required this.userName,
    required this.coverUrl,
    required this.isOpeningBook,
    required this.onCardTap,
    required this.onBookTap,
    required this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onCardTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 书名行 → 书籍详情（内层命中优先于卡片）。
                CommentBookTile(
                  title: comment.bookTitle,
                  coverUrl: coverUrl,
                  busy: isOpeningBook,
                  onTap: onBookTap,
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CommentAvatar(
                      avatarUrl: comment.userAvatar,
                      onTap: onAvatarTap,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userName,
                            style: tt.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (comment.text.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            SelectableText(
                              comment.text,
                              style: tt.bodyMedium?.copyWith(height: 1.45),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text(
                                comment.date,
                                style: tt.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 6),
                              CommentMetricChip(
                                // 描边图标：与评论区一致，填充态专指已点赞；
                                // 这里纯展示自己的获赞数。
                                icon: Icons.thumb_up_outlined,
                                count: comment.likeCount,
                                // 纯展示：我的评论页不支持点赞切换。
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
