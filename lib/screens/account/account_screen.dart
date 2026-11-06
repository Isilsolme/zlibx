import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/zlibrary_provider.dart';
import '../../routes/app_routes.dart';
import '../../services/hive_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/gradient_app_bar.dart';

/// Account tab (third nav destination): the signed-in user's profile
/// header plus three entry cards — My Library (the old bookshelf
/// screen, unchanged), My Comments (comments the user posted) and
/// Booklists (own + public booklists, read-only v1).
///
/// The detail page's per-book comments entry is untouched, and the
/// Settings login card stays as the other way back to login.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(authProvider).user;

    return Scaffold(
      appBar: GradientAppBar(title: l10n.get('account')),
      body: user == null
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
              ],
            ),
    );
  }
}

class _ProfileHeader extends ConsumerStatefulWidget {
  final String name;
  final String email;
  final int? downloadsLeft;

  const _ProfileHeader({
    required this.name,
    required this.email,
    required this.downloadsLeft,
  });

  @override
  ConsumerState<_ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends ConsumerState<_ProfileHeader> {
  static const _avatarCacheTtlMs = 7 * 24 * 60 * 60 * 1000;

  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _resolveAvatar();
  }

  void _resolveAvatar() {
    final box = HiveService.settingsBox;
    final cached = box.get('avatarUrl') as String?;
    final savedAt = box.get('avatarUrlSavedAt') as int?;
    if (cached != null &&
        cached.isNotEmpty &&
        savedAt != null &&
        DateTime.now().millisecondsSinceEpoch - savedAt < _avatarCacheTtlMs) {
      _avatarUrl = cached;
      return;
    }
    ref.read(zlibraryApiProvider).getMyAvatarUrl().then((url) {
      if (!mounted || url == null || url.isEmpty) return;
      box.put('avatarUrl', url);
      box.put('avatarUrlSavedAt', DateTime.now().millisecondsSinceEpoch);
      setState(() => _avatarUrl = url);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    // The avatar URL is resolved from the website profile page via the
    // plugin (the eapi profile has none, and the comments `cover` is
    // the profile banner) and cached in Hive for 7 days; any failure
    // keeps the placeholder avatar.
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: cs.primaryContainer,
              child: _avatarUrl == null
                  ? Icon(
                      Icons.person_rounded,
                      size: 32,
                      color: cs.onPrimaryContainer,
                    )
                  : ClipOval(
                      child: Image.network(
                        _avatarUrl!,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.person_rounded,
                          size: 32,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.name.isNotEmpty ? widget.name : widget.email,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.name.isNotEmpty &&
                      widget.email.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.email,
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
                        '：${widget.downloadsLeft ?? '—'}',
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
