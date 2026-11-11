import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../models/display_book.dart';
import '../../providers/category_books_provider.dart';
import '../../routes/app_routes.dart';
import '../../widgets/book_list_tile.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/gradient_app_bar.dart';
import '../../widgets/loading_widget.dart';

// Existing callers (routes) import the args class from this screen's
// library.
export '../../providers/category_books_provider.dart'
    show CategoryBooksArgs;

/// Books in one category: the category name as the title above the
/// book list. Loading, paging and the WebView fallback live in
/// [CategoryBooksController]; tapping a book opens its detail page
/// (the books carry their hash, so the detail loads fully).
class CategoryBooksScreen extends ConsumerStatefulWidget {
  final CategoryBooksArgs args;

  const CategoryBooksScreen({super.key, required this.args});

  @override
  ConsumerState<CategoryBooksScreen> createState() =>
      _CategoryBooksScreenState();
}

class _CategoryBooksScreenState extends ConsumerState<CategoryBooksScreen> {
  final ScrollController _scrollController = ScrollController();

  late final _provider = categoryBooksControllerProvider(widget.args);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 300) {
      ref.read(_provider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(_provider);
    final controller = ref.read(_provider.notifier);

    return Scaffold(
      appBar: GradientAppBar(title: widget.args.categoryName),
      body: RefreshIndicator(
        onRefresh: controller.loadFirst,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: _body(l10n, state),
        ),
      ),
    );
  }

  List<Widget> _body(AppLocalizations l10n, CategoryBooksState state) {
    if (state.isLoading) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 48),
            child: LoadingWidget(message: l10n.loading),
          ),
        ),
      ];
    }
    if (state.error != null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.error_outline,
            title: l10n.error,
            message: state.error,
            action: FilledButton(
              onPressed: () =>
                  ref.read(_provider.notifier).loadFirst(),
              child: Text(l10n.retry),
            ),
          ),
        ),
      ];
    }
    if (state.books.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.category_outlined,
            title: l10n.noCategoryBooks,
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        sliver: SliverList.builder(
          itemCount: state.books.length,
          itemBuilder: (context, index) {
            final book = state.books[index];
            return BookListTile(
              book: book.toDisplay(),
              showCover: true,
              onTap: () => AppRoutes.openBookDetailForBook(context, book),
            );
          },
        ),
      ),
      if (state.isLoadingMore)
        const SliverToBoxAdapter(child: LoadingWidget.more()),
    ];
  }
}
