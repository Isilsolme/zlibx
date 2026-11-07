import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/zlibrary_provider.dart';
import '../../routes/app_routes.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/gradient_app_bar.dart';
import '../../widgets/loading_widget.dart';
import '../comments/book_comments_screen.dart';

/// Another user's profile page, reached by tapping an avatar in a
/// comment row. v1 shows only what the comments endpoint can supply:
/// a header (avatar + name from the tapped comment) and that user's
/// posted comments, newest-first NOT applied — same endpoint order as
/// "My Comments" (the site's own order). Their saved books are NOT
/// shown: `getUserSaved` reads the session user only, and their
/// booklists have no author/user filter, so there is nothing cleanly
/// fetchable for them. Tapping a comment opens that book's comments
/// page, like "My Comments" does.
class UserProfileScreen extends ConsumerStatefulWidget {
  const UserProfileScreen({super.key});

  @override
  ConsumerState<UserProfileScreen> createState() =>
      _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> {
  List<UserCommentEntry> _entries = [];
  bool _isLoading = true;
  bool _loggedIn = true;

  UserProfileArgs get _args =>
      ModalRoute.of(context)!.settings.arguments as UserProfileArgs;

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
    final response =
        await api.getUserComments(_args.userId.toString());
    if (!mounted) return;
    setState(() {
      _entries = response.success && response.data != null
          ? response.data!.entries
          : const [];
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final args = _args;

    return Scaffold(
      appBar: GradientAppBar(title: args.userName),
      body: Column(
        children: [
          _ProfileHeader(args: args),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? LoadingWidget(message: l10n.get('loading'))
                : !_loggedIn
                    ? EmptyState(
                        icon: Icons.login_rounded,
                        title: l10n.get('login_to_view_comments'),
                        action: FilledButton(
                          onPressed: () => Navigator.of(
                            context,
                          ).pushNamed(AppRoutes.login),
                          child: Text(l10n.get('login')),
                        ),
                      )
                    : _entries.isEmpty
                        ? EmptyState(
                            icon: Icons.comment_outlined,
                            title: l10n.get('no_comments'),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                              ),
                              itemCount: _entries.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(
                                    height: 1,
                                    indent: 68,
                                  ),
                              itemBuilder: (context, index) {
                                final entry = _entries[index];
                                return _ProfileCommentCard(
                                  entry: entry,
                                  userName: args.userName,
                                  onTap: () =>
                                      Navigator.of(context).pushNamed(
                                        AppRoutes.bookComments,
                                        arguments: BookCommentsArgs(
                                          bookId: entry.bookId,
                                          bookTitle: entry.bookTitle,
                                        ),
                                      ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

/// Avatar + name of the profile user. The comments endpoint carries
/// no profile header, so this is exactly what the tapped comment
/// showed — nothing is fetched for it.
class _ProfileHeader extends StatelessWidget {
  final UserProfileArgs args;

  const _ProfileHeader({required this.args});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: cs.primaryContainer,
            backgroundImage: args.userAvatar.isNotEmpty
                ? NetworkImage(args.userAvatar)
                : null,
            child: args.userAvatar.isEmpty
                ? Icon(
                    Icons.person_rounded,
                    color: cs.onPrimaryContainer,
                    size: 36,
                  )
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              args.userName,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Same row styling as "My Comments": book header, avatar + name,
/// text, and a bottom row with the date on the left and a read-only
/// like count on the right. The avatar here is not tappable — it is
/// already this profile's user.
class _ProfileCommentCard extends StatelessWidget {
  final UserCommentEntry entry;
  final String userName;
  final VoidCallback onTap;

  const _ProfileCommentCard({
    required this.entry,
    required this.userName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final comment = entry.comment;
    final date = comment.dateRelative.isNotEmpty
        ? comment.dateRelative
        : comment.date;
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
                    entry.bookTitle,
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
                            date,
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
