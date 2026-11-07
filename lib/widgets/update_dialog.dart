import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../services/update_service.dart';
import 'loading_widget.dart';

/// 更新对话框：Release 清单里的下载渠道（网盘等）+ 官网 + GitHub，用户自选。
///
/// 强制更新时不可关闭（返回键 / 点遮罩均无效）。
Future<void> showUpdateDialog(BuildContext context) {
  final forced = UpdateService.forceUpdate;
  return showDialog<void>(
    context: context,
    barrierDismissible: !forced,
    builder: (_) => PopScope(canPop: !forced, child: const _UpdateDialog()),
  );
}

/// 设置页「检查更新」：强制请求一次，有新版本弹更新对话框，否则提示已是最新
Future<void> showManualUpdateCheck(BuildContext context) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(
        children: [
          const LoadingWidget.inline(),
          const SizedBox(width: 20),
          Text(AppLocalizations.of(context).get('checking_updates')),
        ],
      ),
    ),
  );

  final hasUpdate = await UpdateService.checkForUpdate(force: true);
  if (!context.mounted) return;
  Navigator.of(context).pop();

  if (hasUpdate) {
    await showUpdateDialog(context);
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(AppLocalizations.of(context).get('up_to_date_title')),
      content: Text(AppLocalizations.of(context).get('up_to_date_desc')),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(AppLocalizations.of(context).get('got_it')),
        ),
      ],
    ),
  );
}

class _Channel {
  final String name;
  final String url;
  final IconData icon;

  const _Channel(this.name, this.url, this.icon);
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final forced = UpdateService.forceUpdate;
    final notes = UpdateService.getChangelog(isZh ? 'zh' : 'en');

    final channels = [
      for (final l in UpdateService.links)
        _Channel(l.name, l.url, Icons.cloud_download_outlined),
      if (UpdateService.downloadUrl != null)
        _Channel(
          AppLocalizations.of(context).get('website_download'),
          UpdateService.downloadUrl!,
          Icons.language,
        ),
      if (UpdateService.releaseUrl != null)
        _Channel('GitHub', UpdateService.releaseUrl!, Icons.code),
    ];

    return AlertDialog(
      icon: Icon(Icons.system_update, color: cs.primary, size: 32),
      title: Text(
        forced
            ? (AppLocalizations.of(context).get('update_required'))
            : (AppLocalizations.of(context).get('update_found_title').replaceAll('{version}', '${UpdateService.latestVersion}')),
        textAlign: TextAlign.center,
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppLocalizations.of(context).get('update_current_latest').replaceAll('{current}', '${UpdateService.currentVersion}').replaceAll('{latest}', '${UpdateService.latestVersion}'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              if (forced) ...[
                const SizedBox(height: 12),
                Text(
                  AppLocalizations.of(context).get('update_unsupported'),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  constraints: const BoxConstraints(maxHeight: 180),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      notes,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.6,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                AppLocalizations.of(context).get('choose_download_source'),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < channels.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _ChannelButton(channel: channels[i], primary: i == 0),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (!forced)
          TextButton(
            onPressed: () {
              UpdateService.dismissUpdate();
              Navigator.of(context).pop();
            },
            child: Text(AppLocalizations.of(context).get('later')),
          ),
      ],
    );
  }
}

class _ChannelButton extends StatelessWidget {
  final _Channel channel;
  final bool primary;

  const _ChannelButton({required this.channel, required this.primary});

  Future<void> _open(BuildContext context) async {
    var ok = false;
    try {
      ok = await launchUrl(
        Uri.parse(channel.url),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('UpdateDialog: failed to open ${channel.url}: $e');
    }
    // 打不开时把链接显示出来，方便用户手动复制
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: SelectableText(channel.url)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = Row(
      children: [
        Icon(channel.icon, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(channel.name)),
        const Icon(Icons.open_in_new, size: 16),
      ],
    );
    return primary
        ? FilledButton(onPressed: () => _open(context), child: child)
        : OutlinedButton(onPressed: () => _open(context), child: child);
  }
}
