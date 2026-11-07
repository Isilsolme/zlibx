import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/zlibrary_provider.dart';
import '../../routes/app_routes.dart';
import '../../screens/comments/book_comments_screen.dart';
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
/// comments page (view, post, reply, like — already implemented there);
/// deleting a comment is not implemented (delete endpoint unknown).
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

  /// The website's profile Comments tab, confirmed by a packet capture
  /// on 2026-11-06: `GET /papi/comments/user/{userId}/{page}?limit=500`.
  /// Returns an empty list when the request fails (the screen then shows
  /// the empty state; pull-to-refresh retries).
  Future<List<MyComment>> _fetchMyComments() async {
    final api = ref.read(zlibraryApiProvider);
    final response = await api.getMyComments();
    if (!response.success || response.data == null) return const [];
    return response.data!.entries
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

  Future<void> _load() async {
    if (ref.read(authProvider).user == null) {
      setState(() {
        _loggedIn = false;
        _isLoading = false;
      });
      return;
    }
    setState(() => _isLoading = true);
    final comments = await _fetchMyComments();
    if (!mounted) return;
    setState(() {
      _comments = comments;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: GradientAppBar(title: l10n.get('my_comments')),
      body: _isLoading
          ? LoadingWidget(message: l10n.get('loading'))
          : !_loggedIn
              ? EmptyState(
                  icon: Icons.login_rounded,
                  title: l10n.get('login_to_view_comments'),
                  action: FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pushNamed(AppRoutes.login),
                    child: Text(l10n.get('login')),
                  ),
                )
              : _comments.isEmpty
                  ? EmptyState(
                      icon: Icons.comment_outlined,
                      title: l10n.get('no_comments'),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _comments.length,
                        separatorBuilder: (context, index) => const Divider(
                          height: 1,
                          indent: 68,
                        ),
                        itemBuilder: (context, index) {
                          final comment = _comments[index];
                          return _MyCommentCard(
                            comment: comment,
                            userName:
                                ref.read(authProvider).user?.name ?? '',
                            onTap: () => Navigator.of(context).pushNamed(
                              AppRoutes.bookComments,
                              arguments: BookCommentsArgs(
                                bookId: comment.bookId,
                                bookTitle: comment.bookTitle,
                              ),
                            ),
                            onAvatarTap: () =>
                                Navigator.of(context).pushNamed(
                              AppRoutes.userProfile,
                              arguments: UserProfileArgs(
                                userId: comment.userId,
                                userName: ref
                                        .read(authProvider)
                                        .user
                                        ?.name ??
                                    '',
                                userAvatar: comment.userAvatar,
                                userHash: comment.userHash,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

/// Same row styling as the per-book comments list
/// ([book_comments_screen.dart]'s comment row): book header, avatar +
/// name, text, and a bottom row with the date on the left and a
/// read-only like count on the right.
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
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.book_outlined, color: cs.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    comment.bookTitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: onAvatarTap,
                  customBorder: const CircleBorder(),
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: cs.primaryContainer,
                    backgroundImage: comment.userAvatar.isNotEmpty
                        ? NetworkImage(comment.userAvatar)
                        : null,
                    child: comment.userAvatar.isEmpty
                        ? Icon(
                            Icons.person_rounded,
                            color: cs.onPrimaryContainer,
                            size: 22,
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        comment.text,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            comment.date,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
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
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
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
    );
  }
}
