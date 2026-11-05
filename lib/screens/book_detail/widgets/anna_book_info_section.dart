import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/display_book.dart';
import '../../../services/annas_archieve.dart';
import 'book_detail_content.dart';

/// External detail body (Anna's Archive / LibGen): heading + format tag +
/// description + publication info. Built from [BookInfoData] (the detail
/// page's own fetch); the search-result [DisplayBook] supplies
/// title/author/cover. The download button lives in the page's bottom
/// bar (ExternalBookActionBar), not in this section.
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
      l10n.get('source'): l10n.get(
        displayBook.isLibGen ? 'source_libgen' : 'source_annas_archive',
      ),
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
          ],
        ),
      ),
    );
  }
}
