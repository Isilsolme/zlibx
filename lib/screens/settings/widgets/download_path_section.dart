import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../../../providers/settings_provider.dart';
import '../../../utils/file_utils.dart';
import 'section_header.dart';
import 'settings_card.dart';
import '../../../l10n/app_localizations.dart';

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
          title: AppLocalizations.of(context).get('downloads'),
        ),
        SettingsCard(
          child: ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(AppLocalizations.of(context).get('download_directory')),
            subtitle: _buildSubtitle(context, ref),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showDownloadPathDialog(context, ref),
          ),
        ),
      ],
    );
  }

  Widget _buildSubtitle(BuildContext context, WidgetRef ref) {
    if (Platform.isAndroid) {
      return Text(
        AppLocalizations.of(context).get('system_downloads_mediastore'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    final path = ref.watch(downloadPathProvider);
    final displayPath = (path != null && path.isNotEmpty)
        ? path
        : (AppLocalizations.of(context).get('default_app_documents'));
    return Text(
      displayPath,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  void _showDownloadPathDialog(BuildContext context, WidgetRef ref) {

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) =>
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle bar
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // On Android 10+, MediaStore handles downloads automatically
                  if (Platform.isAndroid) ...[
                    ListTile(
                      leading: Icon(
                          Icons.download, color: Theme.of(context).colorScheme.primary),
                      title: Text(
                          AppLocalizations.of(context).get('system_downloads_folder')),
                      subtitle: Text(
                        AppLocalizations.of(context).get('mediastore_desc'),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          AppLocalizations.of(context).get('recommended'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blue[700],
                                size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                AppLocalizations.of(context).get('downloads_saved_hint'),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.blue[700],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final success = await openDownloadFolder();
                                if (!success && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(AppLocalizations.of(context).get('cannot_open_folder'))),
                                  );
                                } else if (context.mounted) {
                                  Navigator.pop(context);
                                }
                              },
                              icon: const Icon(Icons.folder_open),
                              label: Text(AppLocalizations.of(context).get('open_download_folder')),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else
                    ...[
                      // On desktop platforms, use file picker
                      ListTile(
                        leading: Icon(
                            Icons.folder_open, color: Theme.of(context).colorScheme.primary),
                        title: Text(AppLocalizations.of(context).get('select_folder')),
                        subtitle: Text(AppLocalizations.of(context).get('choose_custom_download_dir')),
                        onTap: () async {
                          Navigator.pop(context);
                          final result = await FilePicker
                              .getDirectoryPath();
                          if (result != null) {
                            ref
                                .read(downloadPathProvider.notifier)
                                .setDownloadPath(result);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(AppLocalizations.of(context).get('download_dir_updated')),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          }
                        },
                      ),
                      ListTile(
                        leading: Icon(
                            Icons.restore,
                            color: Theme.of(context).colorScheme.onSurfaceVariant),
                        title: Text(AppLocalizations.of(context).get('reset_to_default')),
                        subtitle: Text(AppLocalizations.of(context).get('use_default_documents_dir')),
                        onTap: () {
                          Navigator.pop(context);
                          ref
                              .read(downloadPathProvider.notifier)
                              .clearDownloadPath();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(AppLocalizations.of(context).get('reset_to_default_dir_done')),
                            ),
                          );
                        },
                      ),
                    ],
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(AppLocalizations.of(context).get('close')),
                  ),
                ],
              ),
            ),
          ),
    );
  }
}
