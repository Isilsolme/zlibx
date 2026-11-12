import 'package:flutter/material.dart';

import '../models/display_book.dart';
import 'book_card_cover.dart';
import 'book_cover_backdrop.dart';

/// Card shell + text layout. The cover (image, placeholder, source badge,
/// Hero flight) lives in [BookCardCover].
class BookCard extends StatefulWidget {
  final DisplayBook book;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool compact;
  final bool showSourceBadge;
  final bool searchResult;

  /// Hero is opt-in: callers that can render the same book twice (home
  /// sections) must not share a tag.
  final bool heroEnabled;

  const BookCard({
    super.key,
    required this.book,
    this.onTap,
    this.onLongPress,
    this.compact = false,
    this.showSourceBadge = false,
    this.searchResult = false,
    this.heroEnabled = false,
  });

  static double compactHeightFor(double width) =>
      BookCoverBackdrop.heightFor(width);

  @override
  State<BookCard> createState() => _BookCardState();
}

class _BookCardState extends State<BookCard> {
  double _scale = 1.0;

  void _onTapDown(TapDownDetails details) {
    setState(() => _scale = 0.96);
  }

  void _onTapUp(TapUpDetails details) {
    setState(() => _scale = 1.0);
  }

  void _onTapCancel() {
    setState(() => _scale = 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderRadius = BorderRadius.circular(
      widget.compact ? 4 : (widget.searchResult ? 12 : 20),
    );

    return AnimatedScale(
      scale: _scale,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: borderRadius,
          // Compact home cards have no shadow: a shadow inside the route
          // transition layer caused black corner fringes on Impeller.
          boxShadow: widget.compact
              ? const <BoxShadow>[]
              : <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTapDown: _onTapDown,
              onTapUp: _onTapUp,
              onTapCancel: _onTapCancel,
              child: InkWell(
                onTap: widget.onTap,
                onLongPress: widget.onLongPress,
                child: widget.compact
                    ? BookCardCover(
                        book: widget.book,
                        compact: true,
                        showSourceBadge: widget.showSourceBadge,
                        heroEnabled: widget.heroEnabled,
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: BookCardCover(
                              book: widget.book,
                              compact: false,
                              searchResult: widget.searchResult,
                              heroEnabled: widget.heroEnabled,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: widget.searchResult
                                ? _buildSearchInfo()
                                : _buildInfo(),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfo() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMetaRow(),
          const SizedBox(height: 4),
          Expanded(
            child: Text(
              widget.book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(height: 1.2, fontSize: 14),
            ),
          ),
          if (widget.book.author != null && widget.book.author!.isNotEmpty)
            Text(
              widget.book.author!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontSize: 11),
            ),
          const SizedBox(height: 8),
          _buildBottomRow(),
        ],
      ),
    );
  }

  Widget _buildSearchInfo() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMetaRow(),
          const SizedBox(height: 4),
          Text(
            widget.book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(height: 1.2, fontSize: 14),
          ),
          if (widget.book.author != null && widget.book.author!.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              widget.book.author!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetaRow() {
    final hasTag = widget.book.tag != null && widget.book.tag!.isNotEmpty;
    final hasTagExtra =
        widget.book.tagExtra != null && widget.book.tagExtra!.isNotEmpty;

    if (!hasTag && !hasTagExtra) {
      return const SizedBox(height: 12);
    }

    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        if (hasTag)
          Flexible(
            child: Text(
              widget.book.tag!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.secondary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
        if (hasTag && hasTagExtra) const SizedBox(width: 4),
        if (hasTagExtra)
          Text(
            hasTag ? '• ${widget.book.tagExtra}' : widget.book.tagExtra!,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 10),
          ),
      ],
    );
  }

  Widget _buildBottomRow() {
    final hasScore = widget.book.score != null && widget.book.score!.isNotEmpty;
    final hasMeta = widget.book.meta != null && widget.book.meta!.isNotEmpty;

    if (!hasScore && !hasMeta) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        if (hasScore) ...[
          Icon(Icons.star_rounded, size: 14, color: cs.secondary),
          const SizedBox(width: 4),
          Text(
            widget.book.score!,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
        ],
        const Spacer(),
        if (hasMeta)
          Text(
            widget.book.meta!,
            style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
          ),
      ],
    );
  }
}
