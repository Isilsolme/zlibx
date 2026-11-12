import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../l10n/s_keys.dart';
import '../providers/domain_provider.dart';
import '../providers/speed_test_provider.dart';
import '../theme/app_colors.dart';
import '../utils/app_snack.dart';
import 'loading_widget.dart';
import 'mirror_trust_dialog.dart';
import 'settings_sheet.dart';

class DomainSelector extends ConsumerWidget {
  final bool compact;
  final Color? color;

  const DomainSelector({super.key, this.compact = false, this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentDomain = ref.watch(domainProvider);
    final domains = ref.watch(domainListProvider);

    final idx = domains.indexOf(currentDomain);
    final label = idx >= 0 ? 'Line ${idx + 1}' : 'Custom';
    final effectiveColor = color ?? Theme.of(context).colorScheme.primary;

    if (compact) {
      return IconButton(
        icon: const Icon(Icons.dns_outlined),
        color: color ?? Theme.of(context).colorScheme.onSurface,
        tooltip: 'Switch Network ($label)',
        onPressed: () => showDomainSelectionSheet(context),
      );
    }

    return InkWell(
      onTap: () => showDomainSelectionSheet(context),
      borderRadius: BorderRadius.circular(30),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: effectiveColor.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dns_outlined, size: 18, color: effectiveColor),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: effectiveColor,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, color: effectiveColor),
          ],
        ),
      ),
    );
  }
}

/// Opens the network picker through the shared M3 settings sheet.
Future<void> showDomainSelectionSheet(BuildContext context) {
  final t = AppLocalizations.of(context);
  return showSettingsSheet(
    context,
    title: t.get(S.selectNetwork),
    child: const DomainSelectionContent(),
    actions: <Widget>[
      Consumer(
        builder: (context, ref, child) {
          final testing = ref.watch(speedTestProvider).testing;
          return TextButton.icon(
            onPressed: testing
                ? null
                : () => ref.read(speedTestProvider.notifier).runTest(),
            icon: const Icon(Icons.speed_rounded, size: 18),
            label: Text(t.get(S.retest)),
          );
        },
      ),
    ],
  );
}

class DomainSelectionContent extends ConsumerWidget {
  const DomainSelectionContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentDomain = ref.watch(domainProvider);
    final domains = ref.watch(domainListProvider);
    final speedState = ref.watch(speedTestProvider);
    final cs = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
          child: Row(
            children: <Widget>[
              if (speedState.testing) ...<Widget>[
                LoadingWidget.inline(
                  value: speedState.results.isEmpty
                      ? null
                      : speedState.testedCount / speedState.results.length,
                ),
                const SizedBox(width: 8),
                Text(
                  '${speedState.testedCount}/${speedState.results.length}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ] else ...<Widget>[
                Text(
                  '${speedState.onlineCount}/${speedState.results.length} ✓',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: speedState.onlineCount > 0
                        ? cs.primary
                        : cs.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        for (final result in speedState.results)
          _DomainTile(
            result: result,
            label: domains.contains(result.domain)
                ? 'Line ${domains.indexOf(result.domain) + 1}'
                : result.domain,
            selected: result.domain == currentDomain,
            onTap: () async {
              final trusted = await confirmMirrorTrust(
                context,
                result.domain,
                builtIn: true,
              );
              if (!trusted || !context.mounted) return;
              ref.read(domainProvider.notifier).setDomain(result.domain);
              Navigator.pop(context);
            },
          ),
        SettingsOptionTile(
          leading: Icon(
            !domains.contains(currentDomain)
                ? Icons.check_circle_rounded
                : Icons.edit_outlined,
            color: !domains.contains(currentDomain)
                ? cs.primary
                : cs.onSurfaceVariant,
            size: 20,
          ),
          title: !domains.contains(currentDomain)
              ? t.get(S.customLine)
              : t.get(S.customLineEllipsis),
          selected: !domains.contains(currentDomain),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: cs.onSurfaceVariant,
          ),
          onTap: () => _showCustomDomainDialog(context, ref),
        ),
      ],
    );
  }

  void _showCustomDomainDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    final l = AppLocalizations.of(context);

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.get(S.customLineDialogTitle)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l.get(S.domainUrl),
            hintText: 'e.g., example.com',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l.get(S.cancel)),
          ),
          FilledButton(
            onPressed: () {
              final raw = DomainNotifier.normalizeCustomDomain(controller.text);
              if (raw.isEmpty) return;
              if (!DomainNotifier.isValidCustomDomain(raw)) {
                showAppSnack(dialogContext, l.get(S.customDomainInvalid));
                return;
              }
              if (DomainNotifier.isBuiltInDomain(raw)) {
                ref.read(domainProvider.notifier).setCustomDomain(raw);
                Navigator.pop(dialogContext);
                Navigator.pop(context);
                return;
              }
              showDialog<void>(
                context: dialogContext,
                builder: (warnCtx) => AlertDialog(
                  title: Text(l.get(S.customDomainWarningTitle)),
                  content: Text(l.get(S.customDomainWarningBody)),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.pop(warnCtx),
                      child: Text(l.get(S.cancel)),
                    ),
                    FilledButton(
                      onPressed: () {
                        ref.read(domainProvider.notifier).setCustomDomain(raw);
                        Navigator.pop(warnCtx);
                        Navigator.pop(dialogContext);
                        Navigator.pop(context);
                        showAppSnack(context, l.get(S.customDomainReloginHint));
                      },
                      child: Text(l.get(S.customDomainSwitchAnyway)),
                    ),
                  ],
                ),
              );
            },
            child: Text(l.get(S.save)),
          ),
        ],
      ),
    ).whenComplete(
      () => Future<void>.delayed(
        const Duration(milliseconds: 400),
        controller.dispose,
      ),
    );
  }
}

class _DomainTile extends StatelessWidget {
  const _DomainTile({
    required this.result,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final DomainTestResult result;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = domainLatencyStatus(result.latencyMs);
    final latency = result.latencyMs;

    Widget trailing;
    if (status == DomainLatencyStatus.untested) {
      trailing = const LoadingWidget.inline();
    } else if (status == DomainLatencyStatus.unavailable) {
      trailing = Icon(Icons.close_rounded, size: 18, color: cs.error);
    } else {
      final color = status == DomainLatencyStatus.normal
          ? AppColors.success
          : AppColors.warning;
      trailing = Text(
        '${latency ?? 0}ms',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      );
    }

    return SettingsOptionTile(
      leading: Icon(
        selected ? Icons.check_circle_rounded : Icons.circle_outlined,
        color: selected ? cs.primary : cs.onSurfaceVariant,
        size: 20,
      ),
      title: label,
      selected: selected,
      trailing: trailing,
      onTap: onTap,
    );
  }
}
