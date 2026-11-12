import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../../../providers/settings_provider.dart';
import '../../../utils/file_utils.dart';
import 'section_header.dart';
import 'settings_card.dart';
import '../../../widgets/settings_sheet.dart';
import '../../../l10n/app_localizations.dart';

import '../../../utils/app_snack.dart';
import '../../../l10n/s_keys.dart';

class DownloadPathSection extends ConsumerWidget {
  const DownloadPathSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        SectionHeader(
          icon: Icons.download_rounded,
          title: AppLocalizations.of(context).get(S.downloads),
        ),
        SettingsCard(
          child: ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(AppLocalizations.of(context).get(S.downloadDirectory)),
            subtitle: _buildSubtitle(context, ref),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showDownloadPathSheet(context, ref),
          ),
        ),
      ],
    );
  }

  Widget _buildSubtitle(BuildContext context, WidgetRef ref) {
    if (Platform.isAndroid) {
      return Text(
        AppLocalizations.of(context).get(S.systemDownloadsMediastore),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    final path = ref.watch(downloadPathProvider);
    final displayPath = (path != null && path.isNotEmpty)
        ? path
        : AppLocalizations.of(context).get(S.defaultAppDocuments);
    return Text(displayPath, maxLines: 1, overflow: TextOverflow.ellipsis);
  }

  void _showDownloadPathSheet(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    showSettingsSheet(
      context,
      title: t.get(S.downloadDirectory),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (Platform.isAndroid) ...[
            SettingsOptionTile(
              icon: Icons.download_rounded,
              title: t.get(S.systemDownloadsFolder),
              subtitle: t.get(S.mediastoreDesc),
              trailing: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  t.get(S.recommended),
                  style: TextStyle(
                    color: cs.onPrimaryContainer,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: cs.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        t.get(S.downloadsSavedHint),
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () async {
                    final success = await openDownloadFolder();
                    if (!context.mounted) return;
                    if (success) {
                      Navigator.pop(context);
                    } else {
                      showAppSnack(context, t.get(S.cannotOpenFolder));
                    }
                  },
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: Text(t.get(S.openDownloadFolder)),
                ),
              ),
            ),
          ] else ...[
            SettingsOptionTile(
              icon: Icons.folder_open_rounded,
              title: t.get(S.selectFolder),
              subtitle: t.get(S.chooseCustomDownloadDir),
              onTap: () async {
                Navigator.pop(context);
                final result = await FilePicker.getDirectoryPath();
                if (result == null) return;
                ref.read(downloadPathProvider.notifier).setDownloadPath(result);
                if (context.mounted) {
                  showAppSnack(context, t.get(S.downloadDirUpdated));
                }
              },
            ),
            SettingsOptionTile(
              icon: Icons.restore_rounded,
              title: t.get(S.resetToDefault),
              subtitle: t.get(S.useDefaultDocumentsDir),
              onTap: () {
                Navigator.pop(context);
                ref.read(downloadPathProvider.notifier).clearDownloadPath();
                showAppSnack(context, t.get(S.resetToDefaultDirDone));
              },
            ),
          ],
        ],
      ),
    );
  }
}
