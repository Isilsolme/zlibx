import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../routes/app_routes.dart';
import '../../widgets/empty_state.dart';

/// Account tab (third nav destination): the signed-in user's profile
/// header plus four entry cards — My Library (the old bookshelf
/// screen, unchanged), My Comments (comments the user posted),
/// Booklists (own + public booklists, read-only v1) and Download
/// History (cloud — books downloaded on any device, moved here from
/// Settings).
///
/// No AppBar: as a tab the page starts below the status bar (SafeArea)
/// and the bottom nav already says where you are. The detail page's
/// per-book comments entry is untouched, and the Settings login card
/// stays as the other way back to login.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(authProvider).user;

    return Scaffold(
      body: SafeArea(
        top: true,
        bottom: false,
        child: user == null
            ? EmptyState(
                icon: Icons.person_outlined,
                title: l10n.get('login_to_continue'),
                action: FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pushNamed(AppRoutes.login),
                  child: Text(l10n.get('login')),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _ProfileHeader(
                    name: user.name,
                    email: user.email,
                    downloadsLeft: user.downloadsLeft,
                  ),
                  const SizedBox(height: 16),
                  _EntryCard(
                    icon: Icons.library_books_outlined,
                    title: l10n.get('my_library'),
                    subtitle: l10n.get('my_library_subtitle'),
                    onTap: () =>
                        Navigator.of(context).pushNamed(AppRoutes.favorites),
                  ),
                  const SizedBox(height: 12),
                  _EntryCard(
                    icon: Icons.comment_outlined,
                    title: l10n.get('my_comments'),
                    subtitle: l10n.get('my_comments_subtitle'),
                    onTap: () =>
                        Navigator.of(context).pushNamed(AppRoutes.myComments),
                  ),
                  const SizedBox(height: 12),
                  _EntryCard(
                    icon: Icons.collections_bookmark_outlined,
                    title: l10n.get('booklists'),
                    subtitle: l10n.get('booklists_subtitle'),
                    onTap: () =>
                        Navigator.of(context).pushNamed(AppRoutes.booklists),
                  ),
                  const SizedBox(height: 12),
                  _EntryCard(
                    icon: Icons.history,
                    title: l10n.get('download_history'),
                    subtitle: l10n.get('books_downloaded_any_device'),
                    onTap: () =>
                        Navigator.of(context).pushNamed(AppRoutes.history),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final String name;
  final String email;
  final int? downloadsLeft;

  const _ProfileHeader({
    required this.name,
    required this.email,
    required this.downloadsLeft,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    // Text avatar: a solid circle with the first character of the
    // display name. There is no photo to load — the eapi profile has
    // no avatar, and the website profile page sits behind the mirror's
    // browser check, so the earlier fetch-based avatar is gone.
    final initial = name.isNotEmpty
        ? name[0]
        : (email.isNotEmpty ? email[0].toUpperCase() : '');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: cs.primary,
              child: initial.isEmpty
                  ? Icon(
                      Icons.person_rounded,
                      size: 32,
                      color: cs.onPrimary,
                    )
                  : Text(
                      initial,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: cs.onPrimary,
                      ),
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isNotEmpty ? name : email,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (name.isNotEmpty && email.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      email,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.cloud_download_outlined,
                        size: 16,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${l10n.get('downloads_left_today')}'
                        '：${downloadsLeft ?? '—'}',
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
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _EntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          child: Icon(icon, color: cs.onPrimaryContainer),
        ),
        title: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: cs.onSurfaceVariant,
        ),
        onTap: onTap,
      ),
    );
  }
}
