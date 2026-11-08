import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';
import '../../providers/books_provider.dart';
import '../../widgets/cover_placeholder.dart';
import '../../widgets/gradient_app_bar.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/empty_state.dart';
import '../../routes/app_routes.dart';
import '../../l10n/app_localizations.dart';

import '../../l10n/s_keys.dart';
import '../../utils/cover_cache.dart';
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // This provider gets "downloaded" books from account (Cloud history)
    final downloadedBooksAsync = ref.watch(downloadedBooksProvider);

    return Scaffold(
      appBar: GradientAppBar(title: l10n.get(S.downloadHistory)),
      body: downloadedBooksAsync.when(
        data: (books) {
          if (books.isEmpty) {
            return EmptyState(
              icon: Icons.history,
              title: l10n.get(S.noHistory),
              message: l10n.get(S.historyEmptyMessage),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: books.length,
            itemBuilder: (context, index) {
              final book = books[index];
              
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  leading: _HistoryCoverThumb(book: book),
                  title: Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (book.author != null) Text(book.author!),
                      if (book.filesizeString != null)
                        Text(
                          '${book.extension?.toUpperCase()} • ${book.filesizeString}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).pushNamed(
                      AppRoutes.bookDetail,
                      arguments: book,
                    );
                  },
                ),
              );
            },
          );
        },
        loading: () => LoadingWidget(message: l10n.get(S.loadingDownloads)),
        error: (error, stack) => EmptyState(
          icon: Icons.error_outline,
          title: l10n.get(S.error),
          message: error.toString(),
        ),
      ),
    );
  }
}

/// Leading cover for one cloud history row. Tries the listed cover
/// first; when it fails, resolves the detail endpoint's cover once
/// and swaps to it. A row with no listed cover keeps the plain icon.
class _HistoryCoverThumb extends ConsumerWidget {
  const _HistoryCoverThumb({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved = ref.watch(
      historyCoverProvider.select((covers) => covers[book.id.toString()]),
    );
    final cover = resolved ?? book.cover;
    if (cover == null || cover.isEmpty) {
      return const Icon(Icons.book, size: 50);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: cover,
        width: 50,
        height: 70,
        fit: BoxFit.cover,
        memCacheWidth: coverCacheWidth(50, context),
        placeholder: (context, url) => const CoverPlaceholder.static(),
        errorWidget: (context, url, error) {
          if (resolved == null) {
            ref.read(historyCoverProvider.notifier).resolveCover(book);
          }
          return const CoverPlaceholder.static();
        },
      ),
    );
  }
}
