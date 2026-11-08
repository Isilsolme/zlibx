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
/// comments page; tapping the book-title row opens the book's detail
/// page (the user-comments API carries no book hash, so it is resolved
/// by a title search first — see [_MyCommentsScreenState._openBookDetail]).
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

  /// 正在解析书 hash 并准备跳详情的 bookId：行尾转圈，防重复点击。
  final Set<int> _openingBookIds = {};

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
  /// eapi hash（[ZLibraryApi.resolveEapiHash]），再带最小 [Book] 进
  /// 详情页，由 `bookDetailsProvider` 拉取完整信息。
  ///
  /// 解析中该书名行尾转圈；失败提示且不跳转（不进残缺详情页）。
  Future<void> _openBookDetail(MyComment comment) async {
    if (comment.bookId <= 0 || _openingBookIds.contains(comment.bookId)) {
      return;
    }
    setState(() => _openingBookIds.add(comment.bookId));
    try {
      final api = ref.read(zlibraryApiProvider);
      final hash =
          await api.resolveEapiHash('${comment.bookId}', comment.bookTitle);
      if (!mounted) return;
      if (hash == null || hash.isEmpty) {
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
/// 书名行（点击 → 书籍详情）+ 头像/昵称/正文/日期与点赞数。
/// 点卡片其余区域进入该书的评论区。
class _MyCommentCard extends StatelessWidget {
  final MyComment comment;
  final String userName;

  /// 书 hash 解析中：书名行尾显示转圈并禁止再次点击。
  final bool isOpeningBook;
  final VoidCallback onCardTap;
  final VoidCallback onBookTap;
  final VoidCallback onAvatarTap;

  const _MyCommentCard({
    required this.comment,
    required this.userName,
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
                // 书名行 → 书籍详情（内层 InkWell 命中优先于卡片）。
                InkWell(
                  onTap: isOpeningBook ? null : onBookTap,
                  borderRadius: BorderRadius.circular(10),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.book_outlined,
                          size: 19,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          comment.bookTitle,
                          style: tt.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (isOpeningBook)
                        const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          ),
                        )
                      else
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 22,
                          color: cs.outline,
                        ),
                    ],
                  ),
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
