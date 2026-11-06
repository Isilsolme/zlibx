import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
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

  const MyComment({
    required this.bookId,
    required this.bookTitle,
    required this.text,
    required this.date,
    this.likeCount = 0,
  });
}

/// "My Comments": the signed-in user's own posted comments, the same
/// collection the website shows on the profile Comments tab.
///
/// The list endpoint is NOT confirmed yet, so [_fetchMyComments] is a
/// clearly-marked TODO that returns an empty list for now and the
/// screen shows the "endpoint pending" empty state. Do NOT guess a URL
/// here. Tapping a comment opens that book's comments page (view,
/// post, reply, like — already implemented there); deleting a comment
/// is not implemented (delete endpoint unknown).
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

  /// TODO: the "my comments" list endpoint is NOT confirmed yet. The
  /// website's profile Comments tab is the source of this data; capture
  /// its request (desktop DevTools, same as the book-comments capture
  /// on 2026-11-06) and wire it here. Until then this deliberately
  /// returns an empty list — do NOT guess a URL.
  Future<List<MyComment>> _fetchMyComments() async {
    return const [];
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
                      title: l10n.get('my_comments_pending'),
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
                          );
                        },
                      ),
                    ),
    );
  }
}

/// Same card styling as the per-book comments list
/// ([book_comments_screen.dart]'s comment row): book header, avatar +
/// name + date, text, and a read-only like count.
class _MyCommentCard extends StatelessWidget {
  final MyComment comment;
  final String userName;
  final VoidCallback onTap;

  const _MyCommentCard({
    required this.comment,
    required this.userName,
    required this.onTap,
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
                CircleAvatar(
                  radius: 20,
                  backgroundColor: cs.primaryContainer,
                  child: Icon(
                    Icons.person_rounded,
                    color: cs.onPrimaryContainer,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              userName,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            comment.date,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        comment.text,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (comment.likeCount > 0) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
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
