import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/display_book.dart';
import '../../../services/annas_archieve.dart';
import 'book_detail_content.dart';

/// Anna's Archive detail body: heading + format tag + description +
/// publication info. Built from [BookInfoData] (the detail page's own
/// fetch); the search-result [DisplayBook] supplies title/author/cover.
///
/// There is deliberately no download button in Stage 1 — Anna download
/// lands in Stage 3, so the section ends with a short "coming soon" note
/// instead of a dead button.
class AnnaBookInfoSection extends StatelessWidget {
  final DisplayBook displayBook;
  final BookInfoData info;

  const AnnaBookInfoSection({
    super.key,
    required this.displayBook,
    required this.info,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final tags = <Widget>[
      if (info.format?.isNotEmpty ?? false)
        BookDetailTag(
          icon: Icons.description_outlined,
          text: info.format!.toUpperCase(),
          highlight: true,
        ),
    ];
    final fields = <String, String>{
      if (info.publisher?.isNotEmpty ?? false)
        l10n.get('publisher'): info.publisher!,
      l10n.get('source'): l10n.get('source_annas_archive'),
    };

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BookDetailHeading(book: displayBook),
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: tags),
            ],
            if (info.description?.isNotEmpty ?? false) ...[
              const SizedBox(height: 28),
              BookDetailDescription(text: info.description!),
            ],
            if (fields.isNotEmpty) ...[
              const SizedBox(height: 28),
              BookPublicationInfo(fields: fields),
            ],
            const SizedBox(height: 24),
            Divider(
              height: 1,
              color: cs.outlineVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.download_outlined,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.get('annas_download_coming_soon'),
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                    ),
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
