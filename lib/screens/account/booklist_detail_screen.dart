import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

import '../../l10n/app_localizations.dart';
import '../../models/display_book.dart';
import '../../providers/zlibrary_provider.dart';
import '../../routes/app_routes.dart';
import '../../widgets/book_list_tile.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/gradient_app_bar.dart';
import '../../widgets/loading_widget.dart';

/// Arguments for BooklistDetailScreen.
class BooklistDetailArgs {
  final Booklist booklist;

  const BooklistDetailArgs({required this.booklist});
}

/// Books inside one booklist, from
/// `GET /papi/booklist/{id}/get-books/{page}` (JSON, 1-based pages).
/// Tapping a book opens its detail page; list books carry no `hash`,
/// so the detail page renders from the list data, like any hash-less
/// Book in the app.
class BooklistDetailScreen extends ConsumerStatefulWidget {
  final BooklistDetailArgs args;

  const BooklistDetailScreen({super.key, required this.args});

  @override
  ConsumerState<BooklistDetailScreen> createState() =>
      _BooklistDetailScreenState();
}

class _BooklistDetailScreenState extends ConsumerState<BooklistDetailScreen> {
  final ScrollController _scrollController = ScrollController();
  final List<Book> _books = [];
  int _nextPage = 1;
  bool _hasMore = true;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFirst());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _isLoadingMore || _isLoading || _hasError) return;
    if (_scrollController.position.extentAfter < 300) {
      _loadPage(_nextPage);
    }
  }

  Future<void> _loadFirst() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _books.clear();
      _nextPage = 1;
      _hasMore = true;
    });
    await _loadPage(1);
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPage(int page) async {
    final api = ref.read(zlibraryApiProvider);
    if (page > 1) {
      setState(() => _isLoadingMore = true);
    }
    try {
      final response = await api.getBooklistBooks(
        widget.args.booklist.id,
        page: page,
      );
      if (!mounted) return;
      if (response.success && response.data != null) {
        final data = response.data!;
        setState(() {
          _books.addAll(data.books);
          _hasMore = page < data.totalPages;
          _nextPage = page + 1;
          _isLoadingMore = false;
        });
      } else {
        setState(() {
          _isLoadingMore = false;
          if (page == 1) {
            _hasError = true;
            _errorMessage = response.error ?? 'Failed to load booklist';
          } else {
            _hasMore = false;
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
        if (page == 1) {
          _hasError = true;
          _errorMessage = e.toString();
        } else {
          _hasMore = false;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final booklist = widget.args.booklist;

    return Scaffold(
      appBar: GradientAppBar(title: booklist.name),
      body: Column(
        children: [
          // List context header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.collections_bookmark_outlined,
                      color: cs.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        booklist.name,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (booklist.count != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        l10n
                            .get('booklist_book_count')
                            .replaceAll(
                              '{count}',
                              booklist.count.toString(),
                            ),
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
                if (booklist.author.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    booklist.author,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (booklist.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    booklist.description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          // Results
          Expanded(
            child: _isLoading
                ? LoadingWidget(message: l10n.get('loading'))
                : _hasError
                    ? EmptyState(
                        icon: Icons.error_outline,
                        title: l10n.get('error'),
                        message: _errorMessage,
                        action: FilledButton(
                          onPressed: _loadFirst,
                          child: Text(l10n.get('retry')),
                        ),
                      )
                    : _books.isEmpty
                        ? EmptyState(
                            icon: Icons.collections_bookmark_outlined,
                            title: l10n.get('no_booklist_books'),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadFirst,
                            child: ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              itemCount:
                                  _books.length + (_isLoadingMore ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index >= _books.length) {
                                  return const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }
                                final book = _books[index];
                                return BookListTile(
                                  book: book.toDisplay(),
                                  onTap: () {
                                    Navigator.of(context).pushNamed(
                                      AppRoutes.bookDetail,
                                      arguments: book,
                                    );
                                  },
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
