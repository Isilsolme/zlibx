import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/s_keys.dart';
import '../../../providers/booklists_provider.dart';
import '../../../providers/zlibrary_provider.dart';
import '../../../utils/app_snack.dart';

/// Picker for the signed-in user's own booklists; adds [bookId] to the
/// picked list (`GET /papi/booklist/{id}/add-book/{bookId}`).
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
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(booklistsControllerProvider);
    if (state.tab != BooklistTab.mine) {
      // The picker only ever shows the user's own lists; the shared
      // controller may currently sit on the discover tab.
      Future.microtask(
        () => ref
            .read(booklistsControllerProvider.notifier)
            .setTab(BooklistTab.mine),
      );
    }
    return AlertDialog(
      title: Text(l10n.get(S.selectBooklist)),
      content: SizedBox(
        width: double.maxFinite,
        child: _body(l10n, state),
      ),
      actions: [
        TextButton(
          onPressed:
              _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.get(S.cancel)),
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
            Text(l10n.get(S.loginToViewBooklists)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.get(S.login)),
            ),
          ],
        );
      case BooklistsPhase.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(state.error ?? l10n.get(S.error)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () =>
                  ref.read(booklistsControllerProvider.notifier).loadFirst(),
              child: Text(l10n.get(S.retry)),
            ),
          ],
        );
      case BooklistsPhase.ready:
        if (state.lists.isEmpty) {
          return Text(l10n.get(S.noBooklists));
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
                            l10n
                                .get(S.booklistBookCount)
                                .replaceAll('{count}', '${list.count}'),
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
      showAppSnack(
        context,
        AppLocalizations.of(context).get(S.addToBooklistSuccess),
      );
      Navigator.of(context).pop(false);
      return;
    }
    setState(() => _busy = false);
    showAppSnack(
      context,
      AppLocalizations.of(context)
          .get(S.addToBooklistFailed)
          .replaceAll('{error}', response.error ?? ''),
    );
  }
}
