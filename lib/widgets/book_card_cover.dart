import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../l10n/app_localizations.dart';
import '../models/display_book.dart';
import '../utils/cover_cache.dart';
import 'book_cover_backdrop.dart';
import 'cover_placeholder.dart';

/// The image half of a BookCard: the compact full-bleed home cover or the
/// full-card cover. Keeping it separate leaves the card shell and text layout
/// in BookCard and makes the cover/Hero/cache policy reusable.
class BookCardCover extends StatelessWidget {
  const BookCardCover({
    super.key,
    required this.book,
    required this.compact,
    this.showSourceBadge = false,
    this.searchResult = false,
    this.heroEnabled = false,
  });

  final DisplayBook book;
  final bool compact;
  final bool showSourceBadge;
  final bool searchResult;
  final bool heroEnabled;

  bool get _hasCover => book.cover?.isNotEmpty ?? false;

  @override
  Widget build(BuildContext context) {
    return compact ? _buildCompact(context) : _buildFull(context);
  }

  Widget _buildCompact(BuildContext context) {
    final sourceLabel = showSourceBadge
        ? AppLocalizations.of(context).get('source_zlibrary')
        : null;

    Widget content({ImageProvider? image, bool loading = false}) {
      final cover = BookCoverBackdrop(
        image: image,
        placeholder: loading
            ? _buildShimmer(showBookInfo: true)
            : _buildPlaceholder(showBookInfo: true),
        book: book,
        sourceLabel: sourceLabel,
      );
      if (sourceLabel == null) return cover;

      return Stack(
        fit: StackFit.expand,
        children: [
          cover,
          Positioned(
            top: 6,
            left: 6,
            right: 6,
            child: Align(
              alignment: Alignment.topRight,
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: _buildSourceBadge(context, sourceLabel),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (!_hasCover) return content();

    // Decode at the rendered width; height follows BookCoverBackdrop's 0.7
    // aspect ratio, so the cache always matches the card.
    return LayoutBuilder(
      builder: (context, constraints) {
        final cacheWidth = coverCacheWidth(constraints.maxWidth, context);
        final cacheHeight = coverCacheHeight(
          BookCoverBackdrop.heightFor(constraints.maxWidth),
          context,
        );
        return CachedNetworkImage(
          imageUrl: book.cover!,
          memCacheWidth: cacheWidth,
          memCacheHeight: cacheHeight,
          fadeInDuration: const Duration(milliseconds: 300),
          fadeOutDuration: const Duration(milliseconds: 100),
          httpHeaders: const {'Connection': 'keep-alive'},
          imageBuilder: (context, imageProvider) {
            return _maybeHero(content(image: imageProvider));
          },
          placeholder: (context, url) => content(loading: true),
          errorWidget: (context, url, error) => content(),
        );
      },
    );
  }

  Widget _buildFull(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cacheWidth = coverCacheWidth(constraints.maxWidth, context);
        final score = book.score;
        final meta = book.meta;
        final hasScore = score != null && score.isNotEmpty;
        final hasMeta = meta != null && meta.isNotEmpty;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (_hasCover)
              CachedNetworkImage(
                imageUrl: book.cover!,
                fit: BoxFit.cover,
                memCacheWidth: cacheWidth,
                fadeInDuration: const Duration(milliseconds: 300),
                fadeOutDuration: const Duration(milliseconds: 100),
                httpHeaders: const {'Connection': 'keep-alive'},
                imageBuilder: (context, imageProvider) {
                  return _maybeHero(
                    Image(image: imageProvider, fit: BoxFit.cover),
                  );
                },
                errorWidget: (context, url, error) => _buildPlaceholder(),
                placeholder: (context, url) => _buildShimmer(),
              )
            else
              _buildPlaceholder(),
            if (searchResult && (hasScore || hasMeta))
              Positioned(
                right: 8,
                bottom: 8,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (hasScore) _buildCoverLabel(score, rating: true),
                    if (hasScore && hasMeta) const SizedBox(height: 4),
                    if (hasMeta) _buildCoverLabel(meta),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  /// Only image-backed covers participate: placeholder-only cards on the
  /// same screen must not collide on the Hero tag.
  Widget _maybeHero(Widget cover) {
    if (!heroEnabled) return cover;
    return Hero(tag: 'cover-${book.id}', child: cover);
  }

  Widget _buildCoverLabel(String text, {bool rating = false}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (rating) ...[
              const Icon(
                Icons.star_rounded,
                size: 14,
                color: Color(0xFFFFD76A),
              ),
              const SizedBox(width: 3),
            ],
            Text(
              text,
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: rating ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceBadge(BuildContext context, String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
      decoration: BoxDecoration(
        // Quiet translucent charcoal: white text stays legible on any cover
        // without the old saturated blue block shouting over the artwork.
        color: Colors.black.withValues(alpha: isDark ? 0.42 : 0.52),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.library_books_rounded,
            size: 11,
            color: Colors.white.withValues(alpha: 0.9),
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder({bool showBookInfo = false}) {
    return _withFallbackBookInfo(
      const CoverPlaceholder.static(),
      showBookInfo: showBookInfo,
    );
  }

  Widget _buildShimmer({bool showBookInfo = false}) {
    return _withFallbackBookInfo(
      const CoverPlaceholder.shimmer(),
      showBookInfo: showBookInfo,
    );
  }

  Widget _withFallbackBookInfo(
    Widget background, {
    required bool showBookInfo,
  }) {
    if (!showBookInfo) return background;
    final author = book.author?.trim();
    return Stack(
      fit: StackFit.expand,
      children: [
        background,
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Color(0xCC183327)],
              stops: [0.35, 1],
            ),
          ),
        ),
        Positioned(
          left: 10,
          right: 10,
          bottom: 11,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                book.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              if (author != null && author.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 10.5,
                    height: 1.2,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
