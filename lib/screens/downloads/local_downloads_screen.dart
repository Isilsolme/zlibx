import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/download_provider.dart';
import '../../services/media_store.dart';
import '../../theme/app_colors.dart';
import '../../utils/file_utils.dart';
import '../../widgets/empty_state.dart';

import '../../utils/app_snack.dart';
import '../../utils/date_text.dart';
import '../../l10n/s_keys.dart';
class LocalDownloadsScreen extends ConsumerWidget {
  const LocalDownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final tasks = ref.watch(downloadProvider);
    final ongoing = tasks
        .where((task) => task.status != DownloadStatus.completed)
        .toList();
    final completed =
        tasks.where((task) => task.status == DownloadStatus.completed).toList()
          ..sort(
            (a, b) => (b.downloadedAt ?? DateTime(0)).compareTo(
              a.downloadedAt ?? DateTime(0),
            ),
          );
    ongoing.sort((a, b) => _priority(a.status).compareTo(_priority(b.status)));

    // No nested Scaffold: like the recommendation tab this page sits
    // under the home Scaffold (extendBody: true), so the lists can run
    // behind the floating nav. The header is a plain AppBar in a Column.
    final appBar = AppBar(
      title: Text(l.get(S.downloads)),
      actions: [
        IconButton(
          tooltip: l.get(S.openFolder),
          icon: const Icon(Icons.folder_open_rounded),
          onPressed: () async {
            try {
              final opened = await openDownloadFolder();
              if (!opened && context.mounted) {
                showAppSnack(context, l.get(S.openFolderFailed));
              }
            } catch (error) {
              if (context.mounted) {
                showAppSnack(context, l.get(S.openFolderFailed));
              }
            }
          },
        ),
      ],
      bottom: TabBar(
        indicatorColor: Theme.of(context).colorScheme.primary,
        labelColor: Theme.of(context).colorScheme.primary,
        tabs: [
          Tab(text: '${l.get(S.ongoing)} (${ongoing.length})'),
          Tab(text: '${l.get(S.completed)} (${completed.length})'),
        ],
      ),
    );

    return DefaultTabController(
      length: 2,
      child: Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Column(
          children: [
            SizedBox(
              height:
                  appBar.preferredSize.height + MediaQuery.paddingOf(context).top,
              child: appBar,
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _DownloadList(
                    tasks: ongoing,
                    emptyIcon: Icons.downloading_rounded,
                    emptyTitle: l.get(S.noActiveDownloads),
                    emptyMessage: l.get(S.downloadsAppearHere),
                  ),
                  _DownloadList(
                    tasks: completed,
                    emptyIcon: Icons.check_circle_outline_rounded,
                    emptyTitle: l.get(S.noCompletedDownloads),
                    emptyMessage: l.get(S.downloadedBooksHere),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static int _priority(DownloadStatus status) => switch (status) {
    DownloadStatus.downloading => 0,
    DownloadStatus.pending => 1,
    DownloadStatus.error => 2,
    DownloadStatus.cancelled => 3,
    DownloadStatus.completed => 4,
  };
}

class _DownloadList extends StatelessWidget {
  const _DownloadList({
    required this.tasks,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyMessage,
  });

  final List<DownloadTask> tasks;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return EmptyState(
        icon: emptyIcon,
        title: emptyTitle,
        message: emptyMessage,
      );
    }
    return ListView.separated(
      // Bottom 124 = 28 gap + 96 floating-nav clearance, reserved
      // inside the list so items scroll behind the pill (like the
      // home grid).
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 124),
      itemCount: tasks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, index) => _DownloadItem(task: tasks[index]),
    );
  }
}

class _DownloadItem extends ConsumerWidget {
  const _DownloadItem({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final isActive =
        task.status == DownloadStatus.downloading ||
        task.status == DownloadStatus.pending;
    final isComplete = task.status == DownloadStatus.completed;
    final details = [
      if (task.book.extension?.isNotEmpty ?? false)
        task.book.extension!.toUpperCase(),
      if (task.fileSize != null) _formatSize(task.fileSize!),
      if (task.fileSize == null &&
          (task.book.filesizeString?.isNotEmpty ?? false))
        task.book.filesizeString!,
      if (task.downloadedAt != null) formatDownloadDate(task.downloadedAt!),
    ].join(' · ');

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: SizedBox(
                    width: 64,
                    height: 92,
                    child: task.book.cover?.isNotEmpty == true
                        ? CachedNetworkImage(
                            imageUrl: task.book.cover!,
                            fit: BoxFit.cover,
                            memCacheWidth:
                                (64 * MediaQuery.devicePixelRatioOf(context))
                                    .ceil(),
                            errorWidget: (_, __, ___) => _coverPlaceholder(cs),
                          )
                        : _coverPlaceholder(cs),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        task.book.author?.isNotEmpty == true
                            ? task.book.author!
                            : l.get(S.unknownAuthor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (details.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Text(
                          details,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                      const SizedBox(height: 9),
                      _statusLabel(context, l),
                    ],
                  ),
                ),
              ],
            ),
            if (isActive) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value:
                    task.status == DownloadStatus.pending || task.progress <= 0
                    ? null
                    : task.progress,
                minHeight: 5,
                borderRadius: BorderRadius.circular(5),
              ),
              const SizedBox(height: 4),
              Text(
                task.status == DownloadStatus.pending
                    ? l.get(S.downloadPreparing)
                    : '${(task.progress * 100).round()}%',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
            if (task.status == DownloadStatus.error) ...[
              const SizedBox(height: 8),
              Text(
                task.missingFile
                    ? l.get(S.downloadFileMissing)
                    : task.quotaExceeded
                    ? l.get(S.downloadQuotaExceeded)
                    : task.needsFreshLink
                    ? l.get(S.downloadFreshLinkRequired)
                    : task.error ?? l.get(S.downloadFailed),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.error),
              ),
            ],
            if (task.status == DownloadStatus.cancelled &&
                task.needsFreshLink) ...[
              const SizedBox(height: 8),
              Text(
                l.get(S.downloadFreshLinkRequired),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                if (isComplete)
                  FilledButton.tonalIcon(
                    onPressed: () => _openFile(context, ref),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(l.get(S.openFile)),
                  )
                else if (task.canRetry)
                  FilledButton.tonalIcon(
                    onPressed: () => ref
                        .read(downloadProvider.notifier)
                        .startDownload(task.book),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(l.get(S.retry)),
                  )
                else if (isActive)
                  TextButton.icon(
                    onPressed: () => ref
                        .read(downloadProvider.notifier)
                        .cancelDownload(task.id),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: Text(l.get(S.cancel)),
                  ),
                const Spacer(),
                PopupMenuButton<String>(
                  tooltip: l.get(S.more),
                  onSelected: (value) => _onMenu(context, ref, value),
                  itemBuilder: (_) => [
                    if (isComplete) ...[
                      PopupMenuItem(
                        value: 'details',
                        child: Text(l.get(S.fileDetails)),
                      ),
                      PopupMenuItem(
                        value: 'share',
                        child: Text(l.get(S.share)),
                      ),
                      const PopupMenuDivider(),
                    ],
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        isComplete
                            ? l.get(S.downloadDeleteFile)
                            : l.get(S.downloadRemoveRecord),
                      ),
                    ),
                  ],
                  icon: const Icon(Icons.more_horiz_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _coverPlaceholder(ColorScheme cs) => ColoredBox(
    color: cs.surfaceContainerHighest,
    child: Icon(Icons.menu_book_rounded, color: cs.onSurfaceVariant),
  );

  Widget _statusLabel(BuildContext context, AppLocalizations l) {
    final (label, color) = switch (task.status) {
      DownloadStatus.pending => (
        l.get(S.downloadPreparing),
        Theme.of(context).colorScheme.primary,
      ),
      DownloadStatus.downloading => (l.get(S.downloading), Theme.of(context).colorScheme.primary),
      DownloadStatus.completed => (l.get(S.completed), AppColors.success),
      DownloadStatus.error => (
        l.get(S.downloadFailed),
        Theme.of(context).colorScheme.error,
      ),
      DownloadStatus.cancelled => (
        l.get(S.downloadCancelled),
        Theme.of(context).colorScheme.outline,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  static String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  Future<bool> _fileExists(BuildContext context, WidgetRef ref) async {
    final path = task.filePath;
    if (path != null && await MediaStoreFiles.exists(path)) return true;
    ref.read(downloadProvider.notifier).markMissingFile(task.id);
    if (context.mounted) {
      showAppSnack(context,
            AppLocalizations.of(context).get(S.downloadFileMissing),
          );
    }
    return false;
  }

  Future<void> _openFile(BuildContext context, WidgetRef ref) async {
    if (!await _fileExists(context, ref)) return;
    try {
      // MediaStore-published downloads live at a content:// URI, which
      // OpenFilex cannot open — those go through the platform channel.
      if (MediaStoreFiles.isContentUri(task.filePath!)) {
        final opened = await MediaStoreFiles.open(task.filePath!);
        if (!opened && context.mounted) {
          showAppSnack(context,
                AppLocalizations.of(context).get(S.openFileFailed),
              );
        }
        return;
      }
      final result = await OpenFilex.open(task.filePath!);
      if (result.type != ResultType.done && context.mounted) {
        showAppSnack(context, result.message);
      }
    } catch (error) {
      if (context.mounted) {
        showAppSnack(context, error.toString());
      }
    }
  }

  Future<void> _onMenu(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    final l = AppLocalizations.of(context);
    switch (action) {
      case 'details':
        if (!context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(l.get(S.fileDetails)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.book.title),
                const SizedBox(height: 8),
                if (task.fileSize != null) Text(_formatSize(task.fileSize!)),
                if (task.downloadedAt != null)
                  Text(formatDownloadDate(task.downloadedAt!)),
                const SizedBox(height: 8),
                SelectableText(task.filePath ?? ''),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l.get(S.done)),
              ),
            ],
          ),
        );
        return;
      case 'share':
        if (!await _fileExists(context, ref)) return;
        // MediaStore-published downloads live at a content:// URI,
        // which share_plus cannot share as a file path — those are
        // copied to a temp file in the app cache dir first.
        final sharePath = await MediaStoreFiles.shareablePath(
          task.filePath!,
        );
        if (sharePath == null) {
          if (context.mounted) {
            showAppSnack(context, l.get(S.shareFailed));
          }
          return;
        }
        try {
          await SharePlus.instance.share(
            ShareParams(files: [XFile(sharePath)], text: task.book.title),
          );
        } catch (error) {
          if (context.mounted) {
            showAppSnack(context, l.get(S.shareFailed));
          }
        }
        return;
      case 'delete':
        await _confirmDelete(context, ref);
        return;
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          task.status == DownloadStatus.completed
              ? l.get(S.downloadDeleteFile)
              : l.get(S.downloadRemoveRecord),
        ),
        content: Text(
          task.status == DownloadStatus.completed
              ? l.get(S.deleteDesc)
              : l.get(S.downloadRemoveRecordHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l.get(S.cancel)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l.get(S.delete)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(downloadProvider.notifier).removeTask(task.id);
    } catch (error) {
      if (context.mounted) {
        showAppSnack(context, l.get(S.downloadDeleteFailed));
      }
    }
  }

}
