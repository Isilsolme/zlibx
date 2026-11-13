import 'package:flutter/material.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

import '../../../core/book_description.dart';
import '../../../models/display_book.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../l10n/book_categories.dart';
import '../../../providers/booklist_detail_provider.dart';
import '../../../providers/category_books_provider.dart';
import '../../../routes/app_routes.dart';
import '../../../widgets/booklist_card.dart';
import '../../similar/similar_books_screen.dart';
import '../../comments/book_comments_screen.dart';
import 'add_to_booklist_dialog.dart';
import 'book_detail_content.dart';

class BookInfoSection extends StatelessWidget {
  final Book book;

  /// The booklists the site renders in the detail page's 关联书单
  /// block (parsed from the same HTML fetch as the metadata — see
  /// `parseRelatedBooklists`). Empty when the page has none (most
  /// books) or the fetch failed.
  final List<Booklist> relatedBooklists;

  const BookInfoSection({
    super.key,
    required this.book,
    this.relatedBooklists = const [],
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tags = <Widget>[
      if (book.extension?.isNotEmpty ?? false)
        BookDetailTag(
          icon: Icons.description_outlined,
          text: book.extension!.toUpperCase(),
          highlight: true,
        ),
      if (book.filesizeString?.isNotEmpty ?? false)
        BookDetailTag(icon: Icons.storage_outlined, text: book.filesizeString!),
      if (book.year != null && book.year != 0)
        BookDetailTag(
          icon: Icons.calendar_today_outlined,
          text: '${book.year}',
        ),
      // Detail-page rating (site header block `★ 3.0 / 5.0`): interest
      // over quality. The interest side falls back to the eapi interest
      // score (the ★ the search card shows) when the detail HTML fetch
      // failed — see book_detail_screen.dart; quality is HTML-only.
      // Shown when either score exists; the site hides each span
      // independently for unrated books, and the parser nulls them.
      if ((book.ratingInterest?.isNotEmpty ?? false) ||
          (book.ratingQuality?.isNotEmpty ?? false))
        BookDetailTag(
          icon: Icons.star_rounded,
          text: _ratingText(book),
        ),
      // Website categories (eapi `categories`, e.g. `{307: History -
      // World history}`): one chip per category, localized to the app
      // language (zh / zh_Hant via the category table; other locales show
      // the English name from the API). A chip with a parsed id opens
      // that category's book list; a plain name without an id stays
      // display-only.
      ...parseBookCategories(book.categories).map((c) {
        final locale = Localizations.localeOf(context);
        final tag = BookDetailTag(
          icon: Icons.category_outlined,
          text: localizedBookCategoryName(c, locale),
        );
        final id = c.id;
        if (id == null) return tag;
        return InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => AppRoutes.openCategoryBooks(
            context,
            CategoryBooksArgs(
              categoryId: id,
              categoryName: localizedBookCategoryName(c, locale),
            ),
          ),
          child: tag,
        );
      }),
    ];
    final fields = <String, String>{
      if (book.publisher?.isNotEmpty ?? false)
        l10n.publisher: book.publisher!,
      if (book.pages != null && book.pages != 0)
        l10n.pages: '${book.pages}',
      if (book.language?.isNotEmpty ?? false)
        l10n.language: book.language!,
      // Detail-page-only metadata (parsed from the detail HTML, not
      // the eapi): shown only when the fetch returned them.
      if (book.volume?.isNotEmpty ?? false)
        l10n.volume: book.volume!,
      if (book.isbn13?.isNotEmpty ?? false)
        l10n.isbn13: book.isbn13!,
      if (book.isbn10?.isNotEmpty ?? false)
        l10n.isbn10: book.isbn10!,
      // Both CIDs on their own labelled lines: the Blake2b CID must
      // stay reachable, never silently dropped. Display-only for v1
      // (BookPublicationInfo has no tap-to-copy).
      if (book.ipfsCid?.isNotEmpty ?? false)
        l10n.ipfs: [
          'CID: ${book.ipfsCid!}',
          if (book.ipfsCidBlake2b?.isNotEmpty ?? false)
            'CID Blake2b: ${book.ipfsCidBlake2b!}',
        ].join('\n'),
    };
    // A missing description must stay absent rather than rendering as
    // the literal word "null".
    final description = normalizedBookDescription(book.description);

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BookDetailHeading(
              book: book.toDisplay(),
              subtitle: book.series,
              // Tapping the author searches for that author (the
              // heading only shows the author when it is non-empty,
              // so the callback can only fire then).
              onAuthorTap: book.author?.isNotEmpty ?? false
                  ? () => AppRoutes.openSearchWithQuery(context, book.author!)
                  : null,
            ),
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 16),
              // One row, never wrapped below: a category name can be long,
              // so the row scrolls horizontally instead of dropping tags
              // onto a second line.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < tags.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      tags[i],
                    ],
                  ],
                ),
              ),
            ],
            if (description != null) ...[
              const SizedBox(height: 28),
              BookDetailDescription(text: description),
            ],
            if (fields.isNotEmpty) ...[
              const SizedBox(height: 28),
              BookPublicationInfo(
                fields: fields,
                // Tapping the publisher searches for that publisher
                // (the key is the same localized label used for the
                // row above, so it can only match that row).
                onFieldTap: book.publisher?.isNotEmpty ?? false
                    ? {
                        l10n.publisher: () => AppRoutes.openSearchWithQuery(
                          context,
                          book.publisher!,
                        ),
                      }
                    : null,
              ),
            ],
            // Related booklists (site's 关联书单 block): one horizontal
            // row of compact tiles, each opening the booklist detail
            // page. Same section position as the site's own page.
            if (relatedBooklists.isNotEmpty)
              _RelatedBooklistsSection(booklists: relatedBooklists),
            if (book.hash?.isNotEmpty ?? false) ...[
              const SizedBox(height: 24),
              Divider(
                height: 1,
                color: cs.outlineVariant.withValues(alpha: 0.5),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.auto_stories_outlined,
                  color: cs.primary,
                  size: 22,
                ),
                title: Text(
                  l10n.similarBooks,
                  style: const TextStyle(fontSize: 15),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                onTap: () => AppRoutes.openSimilarBooks(
                  context,
                  SimilarBooksArgs(
                    bookId: book.id,
                    hashId: book.hash!,
                    bookTitle: book.title,
                  ),
                ),
              ),
            ],
            // Add this book to one of the user's own booklists.
            const SizedBox(height: 8),
            Divider(
              height: 1,
              color: cs.outlineVariant.withValues(alpha: 0.5),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.collections_bookmark_outlined,
                color: cs.primary,
                size: 22,
              ),
              title: Text(
                l10n.addToBooklist,
                style: const TextStyle(fontSize: 15),
              ),
              trailing: const Icon(Icons.chevron_right_rounded, size: 20),
              onTap: () => _addToBooklist(context, book),
            ),
            // Book comments (Z-Library site comments, view-only).
            const SizedBox(height: 8),
            Divider(
              height: 1,
              color: cs.outlineVariant.withValues(alpha: 0.5),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.comment_outlined,
                color: cs.primary,
                size: 22,
              ),
              title: Text(
                l10n.comments,
                style: const TextStyle(fontSize: 15),
              ),
              trailing: const Icon(Icons.chevron_right_rounded, size: 20),
              onTap: () => AppRoutes.openBookComments(
                context,
                BookCommentsArgs(
                  bookId: book.id,
                  bookTitle: book.title,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 详情页的「关联书单」区：站点详情页在同一文档里渲染的书单卡
/// （书单名 + 书本数 + 代表书封面堆），横向滚动，点击进书单详情页。
/// 标题与分隔线样式沿用 [BookPublicationInfo] 的区块惯例。
class _RelatedBooklistsSection extends StatelessWidget {
  final List<Booklist> booklists;

  const _RelatedBooklistsSection({required this.booklists});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
        const SizedBox(height: 20),
        Text(
          AppLocalizations.of(context)!.relatedBooklists,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        // 卡片宽 132（站点瓷砖 144 的近似值），行高容纳 132 宽的封面
        // (≈176) 加名称与书本数两行文字。
        SizedBox(
          height: 258,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: booklists.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final list = booklists[index];
              return _RelatedBooklistTile(
                list: list,
                onTap: () => AppRoutes.openBooklistDetail(
                  context,
                  BooklistDetailArgs(booklist: list),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 一张关联书单卡：封面 + 书单名 + 书本数。数据来自
/// [Booklist.fromElement]（topic/quantity/z-cover 堆），没有作者/
/// 浏览量等完整书单页字段，因此不复用整卡 [BooklistCard]。
class _RelatedBooklistTile extends StatelessWidget {
  final Booklist list;
  final VoidCallback onTap;

  const _RelatedBooklistTile({required this.list, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final count = list.count;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 132,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BooklistCover(url: list.coverUrl, width: 132, height: 176),
            const SizedBox(height: 6),
            Text(
              list.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              count == null ? '' : l10n.booklistBookCount(count),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The rating tag's text, in the site's own `interest / quality`
/// shape; a missing score collapses to the one that exists (the site
/// hides each span independently, so a one-sided rating is real).
String _ratingText(Book book) {
  final interest = book.ratingInterest;
  final quality = book.ratingQuality;
  if (interest != null && interest.isNotEmpty && quality != null &&
      quality.isNotEmpty) {
    return '$interest / $quality';
  }
  if (interest != null && interest.isNotEmpty) return interest;
  return quality ?? '';
}

/// Open the my-booklists picker and add this book to the picked list.
/// The picker handles the API call and its notices; this only navigates
/// to the login page when the picker reports the user is signed out.
Future<void> _addToBooklist(BuildContext context, Book book) async {
  final loginRequested = await showAddToBooklistDialog(context, book.id);
  if (loginRequested && context.mounted) {
    await AppRoutes.openLogin(context);
  }
}
