import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/booklists_provider.dart';
import '../../../providers/zlibrary_provider.dart';
import '../../../services/booklist_html_cache.dart';
import '../../../utils/app_snack.dart';

/// Picker for the signed-in user's own booklists; adds [bookId] to the
/// picked list (`GET /papi/booklist/{id}/add-book/{bookId}`).
///
/// The picker reads its own [addToBooklistPickerProvider] instance —
/// never the shared [booklistsControllerProvider] — so opening it
/// cannot flip the booklists screen's tab to mine as a side effect.
///
/// Returns true when the user asked to log in (the caller navigates to
/// the login page); false otherwise. The API call and its notices happen
/// inside the dialog.
Future<bool> showAddToBooklistDialog(BuildContext context, int bookId) async {
  final loginRequested = await showDialog<bool>(
    context: context,
    builder: (context) => _AddToBooklistDialog(bookId: bookId),
  );
  return loginRequested ?? false;
}

class _AddToBooklistDialog extends ConsumerStatefulWidget {
  final int bookId;

  const _AddToBooklistDialog({required this.bookId});

  @override
  ConsumerState<_AddToBooklistDialog> createState() =>
      _AddToBooklistDialogState();
}

class _AddToBooklistDialogState extends ConsumerState<_AddToBooklistDialog> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // The picker's own controller instance (mine tab by default);
    // watching the shared controller here used to flip the
    // booklists screen's tab to mine as a side effect.
    final state = ref.watch(addToBooklistPickerProvider);
    return AlertDialog(
      title: Text(l10n.selectBooklist),
      content: SizedBox(
        width: double.maxFinite,
        child: _body(l10n, state),
      ),
      actions: [
        TextButton(
          onPressed:
              _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }

  Widget _body(AppLocalizations l10n, BooklistsState state) {
    switch (state.phase) {
      case BooklistsPhase.loading:
        return const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        );
      case BooklistsPhase.loggedOut:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.loginToViewBooklists),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.login),
            ),
          ],
        );
      case BooklistsPhase.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(state.error ?? l10n.error),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () =>
                  ref.read(addToBooklistPickerProvider.notifier).loadFirst(),
              child: Text(l10n.retry),
            ),
          ],
        );
      case BooklistsPhase.ready:
        if (state.lists.isEmpty) {
          return Text(l10n.noBooklists);
        }
        // Page 1 only (10 lists) — the picker is a quick pick, not a
        // browser; more lists live on the booklists tab.
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final list in state.lists)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.collections_bookmark_outlined),
                    title: Text(
                      list.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: list.count == null
                        ? null
                        : Text(
                            l10n.booklistBookCount(list.count!),
                          ),
                    onTap: _busy ? null : () => _add(list),
                  ),
              ],
            ),
          ),
        );
    }
  }

  Future<void> _add(Booklist list) async {
    if (_busy) return;
    final listId = int.tryParse(list.id);
    if (listId == null) return;
    setState(() => _busy = true);
    final response = await ref
        .read(zlibraryApiProvider)
        .addBookToBooklist(booklistId: listId, bookId: widget.bookId);
    if (!mounted) return;
    if (response.success) {
      // Sync the add: the target list's cached books are stale now
      // (the book is not in them), and its count is one short. The
      // next detail open re-fetches; the shared controller's count
      // is bumped optimistically. No membership state is shown —
      // whether a repeat add is a no-op or a toggle is unverified,
      // so a repeat tap is left to the server, not faked here.
      final accountId = ref.read(authProvider).user?.id;
      BooklistHtmlCache.invalidateBooklist(list.url, accountId: accountId);
      ref.read(booklistsControllerProvider.notifier).noteBookAdded(list.id);
      showAppSnack(
        context,
        AppLocalizations.of(context)!.addToBooklistSuccess,
      );
      Navigator.of(context).pop(false);
      return;
    }
    setState(() => _busy = false);
    showAppSnack(
      context,
      AppLocalizations.of(context)!.addToBooklistFailed(response.error ?? ''),
    );
  }
}
