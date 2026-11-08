import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

import '../l10n/app_localizations.dart';
import '../l10n/s_keys.dart';
import '../utils/cover_cache.dart';
/// Rounded booklist cover with a soft shadow and a themed placeholder.
class BooklistCover extends StatelessWidget {
  final String url;
  final double width;
  final double height;

  const BooklistCover({
    super.key,
    required this.url,
    this.width = 72,
    this.height = 100,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: cs.primaryContainer,
      child: Center(
        child: Icon(
          Icons.collections_bookmark_rounded,
          size: width * 0.4,
          color: cs.onPrimaryContainer.withValues(alpha: 0.7),
        ),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: width,
          height: height,
          child: url.isEmpty
              ? placeholder
              : CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  // 封面按显示尺寸解码，避免整图占内存。
                  memCacheWidth: coverCacheWidth(width, context),
                  placeholder: (_, __) => placeholder,
                  errorWidget: (_, __, ___) => placeholder,
                ),
        ),
      ),
    );
  }
}

/// Small rounded "icon + text" tag (book count, views).
class BooklistMetaPill extends StatelessWidget {
  final IconData icon;
  final String text;

  const BooklistMetaPill({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: cs.onPrimaryContainer),
            const SizedBox(width: 4),
            Text(
              text,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The booklist's book-count and views pills, in one wrap.
class BooklistMetaPills extends StatelessWidget {
  final Booklist list;

  const BooklistMetaPills({super.key, required this.list});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final count = list.count;
    if (count == null && list.views.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        if (count != null)
          BooklistMetaPill(
            icon: Icons.menu_book_rounded,
            text: l10n.get(S.booklistBookCount).replaceAll('{count}', '$count'),
          ),
        if (list.views.isNotEmpty)
          BooklistMetaPill(
            icon: Icons.visibility_outlined,
            text: list.views,
          ),
      ],
    );
  }
}

/// One booklist as a card: cover, name, creator, meta pills and a short
/// description. Used by the booklists screen.
class BooklistCard extends StatelessWidget {
  final Booklist list;
  final VoidCallback onTap;

  const BooklistCard({super.key, required this.list, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BooklistCover(url: list.coverUrl),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      list.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    if (list.author.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.person_outline_rounded,
                            size: 15,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              list.author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    BooklistMetaPills(list: list),
                    if (list.description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        list.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pulsing placeholder cards shown while the first page loads.
class BooklistSkeletonList extends StatefulWidget {
  final int count;

  const BooklistSkeletonList({super.key, this.count = 6});

  @override
  State<BooklistSkeletonList> createState() => _BooklistSkeletonListState();
}

class _BooklistSkeletonListState extends State<BooklistSkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final block = cs.onSurface.withValues(alpha: 0.08);
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: block,
        borderRadius: BorderRadius.circular(6),
      ),
    );
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(_controller),
      child: Column(
        children: [
          for (var i = 0; i < widget.count; i++)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 72,
                      height: 100,
                      decoration: BoxDecoration(
                        color: block,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          bar(double.infinity, 16),
                          const SizedBox(height: 8),
                          bar(120, 12),
                          const SizedBox(height: 14),
                          bar(90, 22),
                          const SizedBox(height: 12),
                          bar(double.infinity, 10),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
