import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../providers/booklist_detail_provider.dart';
import '../../providers/booklists_provider.dart';
import '../../providers/zlibrary_provider.dart';
import '../../routes/app_routes.dart';
import '../../widgets/booklist_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_widget.dart';
import 'widgets/create_booklist_dialog.dart';

import '../../utils/app_snack.dart';
/// Booklists: the signed-in user's own booklists and public booklists to
/// discover, with search on both. Tapping a list opens its books. The
/// "my booklists" tab can create a new list (`createBooklist`) and
/// delete one (`deleteBooklist`); adding a book to a list lives on the
/// book detail page (`addBookToBooklist`). Removing a book from a list
/// is not wired — its response shape has not been captured.
///
/// Loading, paging, cache and the WebView fallback live in
/// [BooklistsController]; this widget only renders its state.
class BooklistsScreen extends ConsumerStatefulWidget {
  const BooklistsScreen({super.key});

  @override
  ConsumerState<BooklistsScreen> createState() => _BooklistsScreenState();
}

class _BooklistsScreenState extends ConsumerState<BooklistsScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 300) {
      ref.read(booklistsControllerProvider.notifier).loadMore();
    }
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(booklistsControllerProvider.notifier).search('');
  }

  /// Ask for a name (and optional description), create the list on the
  /// account, then reload "my booklists" so the new list shows up.
  Future<void> _createBooklist() async {
    final l10n = AppLocalizations.of(context)!;
    final result = await showDialog<({String title, String description})>(
      context: context,
      builder: (context) => const CreateBooklistDialog(),
    );
    if (result == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(booklistsControllerProvider.notifier);
    final response = await ref
        .read(zlibraryApiProvider)
        .createBooklist(title: result.title, description: result.description);
    if (!mounted) return;
    if (response.success) {
      showAppSnackOn(messenger, l10n.booklistCreated);
      if (ref.read(booklistsControllerProvider).tab == BooklistTab.mine) {
        await controller.loadFirst();
      }
    } else {
      showAppSnackOn(messenger,
            l10n.booklistCreateFailed(response.error ?? ''),
          );
    }
  }

  /// Delete one of the user's own lists: confirm first (destructive),
  /// then the controller's optimistic removal; on failure the list is
  /// restored and the error is shown, on success the tab reloads.
  Future<void> _confirmDelete(Booklist list) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.booklistDeleteConfirm),
        content: Text(l10n.booklistDeleteDesc),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(booklistsControllerProvider.notifier);
    final response = await controller.deleteBooklist(list);
    if (!mounted) return;
    if (response.success) {
      showAppSnackOn(messenger, l10n.booklistDeleted);
      await controller.loadFirst();
    } else {
      showAppSnackOn(
        messenger,
        l10n.booklistDeleteFailed(response.error ?? ''),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(booklistsControllerProvider);
    final controller = ref.read(booklistsControllerProvider.notifier);
    final showFab =
        state.tab == BooklistTab.mine && state.phase != BooklistsPhase.loggedOut;

    return Scaffold(
      floatingActionButton: showFab
          ? FloatingActionButton.extended(
              onPressed: _createBooklist,
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.createBooklist),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar.large(title: Text(l10n.booklists)),
            SliverToBoxAdapter(child: _header(l10n, state, controller)),
            ..._body(l10n, state, controller),
          ],
        ),
      ),
    );
  }

  Widget _header(
    AppLocalizations l10n,
    BooklistsState state,
    BooklistsController controller,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        children: [
          _searchBar(l10n, controller),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<BooklistTab>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: BooklistTab.mine,
                  icon: const Icon(Icons.person_outline_rounded),
                  label: Text(l10n.myBooklists),
                ),
                ButtonSegment(
                  value: BooklistTab.discover,
                  icon: const Icon(Icons.explore_outlined),
                  label: Text(l10n.discoverBooklists),
                ),
              ],
              selected: {state.tab},
              onSelectionChanged: (selected) =>
                  controller.setTab(selected.first),
            ),
          ),
        ],
      ),
    );
  }

  // Capsule search field + soft shadow, matching the library page.
  Widget _searchBar(AppLocalizations l10n, BooklistsController controller) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.2 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _searchController,
        builder: (context, value, _) => TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          onSubmitted: controller.search,
          decoration: InputDecoration(
            hintText: l10n.searchBooklists,
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    tooltip: l10n.clear,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: _clearSearch,
                  ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 14,
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body(
    AppLocalizations l10n,
    BooklistsState state,
    BooklistsController controller,
  ) {
    switch (state.phase) {
      case BooklistsPhase.loading:
        return const [SliverToBoxAdapter(child: BooklistSkeletonList())];
      case BooklistsPhase.loggedOut:
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.login_rounded,
              title: l10n.loginToViewBooklists,
              action: FilledButton(
                onPressed: () => AppRoutes.openLogin(context),
                child: Text(l10n.login),
              ),
            ),
          ),
        ];
      case BooklistsPhase.error:
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.error_outline,
              title: l10n.error,
              message: state.error,
              action: FilledButton(
                onPressed: controller.loadFirst,
                child: Text(l10n.retry),
              ),
            ),
          ),
        ];
      case BooklistsPhase.ready:
        if (state.lists.isEmpty) {
          return [
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.collections_bookmark_outlined,
                title: l10n.noBooklists,
              ),
            ),
          ];
        }
        return [
          SliverList.builder(
            itemCount: state.lists.length,
            itemBuilder: (context, index) {
              final list = state.lists[index];
              return BooklistCard(
                list: list,
                onTap: () => AppRoutes.openBooklistDetail(
                  context,
                  BooklistDetailArgs(
                    booklist: list,
                    canEdit: state.tab == BooklistTab.mine,
                  ),
                ),
                onLongPress: state.tab == BooklistTab.mine
                    ? () => _confirmDelete(list)
                    : null,
              );
            },
          ),
          if (state.isLoadingMore)
            const SliverToBoxAdapter(child: LoadingWidget.more()),
          // Room for the floating action button.
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ];
    }
  }
}
