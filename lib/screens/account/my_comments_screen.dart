import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/zlibrary_provider.dart';
import '../../routes/app_routes.dart';
import '../../screens/comments/book_comments_screen.dart';
import '../../screens/comments/widgets/comment_avatar.dart';
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
/// comments page; deleting is not implemented (delete endpoint unknown).
class MyCommentsScreen extends ConsumerStatefulWidget {
  const MyCommentsScreen({super.key});

  @override
  ConsumerState<MyCommentsScreen> createState() => _MyCommentsScreenState();
}

class _MyCommentsScreenState extends ConsumerState<MyCommentsScreen> {
  List<MyComment> _comments = [];
  bool _isLoading = true;
  bool _loggedIn = true;

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
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: _comments.length,
          itemBuilder: (context, index) {
            final comment = _comments[index];
            final userName = ref.read(authProvider).user?.name ?? '';
            return _MyCommentCard(
              comment: comment,
              userName: userName,
              onTap: () => Navigator.of(context).pushNamed(
                AppRoutes.bookComments,
                arguments: BookCommentsArgs(
                  bookId: comment.bookId,
                  bookTitle: comment.bookTitle,
                ),
              ),
              onAvatarTap: () => Navigator.of(context).pushNamed(
                AppRoutes.userProfile,
                arguments: UserProfileArgs(
                  userId: comment.userId,
                  userName: userName,
                  userAvatar: comment.userAvatar,
                  userHash: comment.userHash,
                ),
              ),
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

/// 卡片化的一条“我的评论”：书目头 + 头像/内容/时间/点赞数，
/// 点击卡片进入该书的评论区。
class _MyCommentCard extends StatelessWidget {
  final MyComment comment;
  final String userName;
  final VoidCallback onTap;
  final VoidCallback onAvatarTap;

  const _MyCommentCard({
    required this.comment,
    required this.userName,
    required this.onTap,
    required this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.book_outlined,
                        size: 16,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        comment.bookTitle,
                        style: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: cs.outline,
                    ),
                  ],
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
                          const SizedBox(height: 4),
                          Text(
                            comment.text,
                            style: tt.bodyMedium?.copyWith(height: 1.45),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text(
                                comment.date,
                                style: tt.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                Icons.thumb_up_outlined,
                                size: 16,
                                color: cs.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                comment.likeCount.toString(),
                                style: tt.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
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
