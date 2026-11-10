import 'package:flutter/material.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

import '../l10n/generated/app_localizations.dart';

/// One booklist row: cover thumb, name, author + book count + views,
/// optional description, chevron. Shared by the booklists screen and
/// the user profile page's booklists section.
class BooklistRow extends StatelessWidget {
  final Booklist list;
  final VoidCallback onTap;

  const BooklistRow({super.key, required this.list, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final meta = [
      if (list.author.isNotEmpty) list.author,
      if (list.count != null)
        l10n.booklistBookCount(list.count!),
      if (list.views.isNotEmpty) list.views,
    ].join(' · ');
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 40,
          height: 56,
          child: list.coverUrl.isEmpty
              ? Container(
                  color: cs.primaryContainer,
                  child: Icon(
                    Icons.collections_bookmark_outlined,
                    color: cs.onPrimaryContainer,
                  ),
                )
              : Image.network(
                  list.coverUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: cs.primaryContainer,
                    child: Icon(
                      Icons.collections_bookmark_outlined,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
        ),
      ),
      title: Text(
        list.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (meta.isNotEmpty)
            Text(
              meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          if (list.description.isNotEmpty)
            Text(
              list.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
        ],
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: cs.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}
