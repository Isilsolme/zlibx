import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../providers/domain_provider.dart';
import '../providers/speed_test_provider.dart';
import '../theme/app_colors.dart';
import 'loading_widget.dart';

import '../utils/app_snack.dart';
import '../l10n/s_keys.dart';
class DomainSelector extends ConsumerWidget {
  final bool compact;
  final Color? color;

  const DomainSelector({super.key, this.compact = false, this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentDomain = ref.watch(domainProvider);
    final domains = ref.watch(domainListProvider);

    // Find line number for current domain
    final idx = domains.indexOf(currentDomain);
    final label = idx >= 0 ? 'Line ${idx + 1}' : 'Custom';
    final effectiveColor = color ?? Theme.of(context).colorScheme.primary;

    if (compact) {
      return IconButton(
        icon: const Icon(Icons.dns_outlined),
        color: color ?? Theme.of(context).colorScheme.onSurface,
        tooltip: 'Switch Network ($label)',
        onPressed: () => _showDialog(context),
      );
    }

    return InkWell(
      onTap: () => _showDialog(context),
      borderRadius: BorderRadius.circular(30),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: effectiveColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: effectiveColor.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.dns_outlined,
              size: 18,
              color: effectiveColor,
            ),
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

  void _showDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const DomainSelectionDialog(),
    );
  }
}

class DomainSelectionDialog extends ConsumerWidget {
  const DomainSelectionDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentDomain = ref.watch(domainProvider);
    final domains = ref.watch(domainListProvider);
    final speedState = ref.watch(speedTestProvider);

    // Build lookup: domain -> DomainTestResult
    final Map<String, DomainTestResult> resultMap = {};
    for (final r in speedState.results) {
      resultMap[r.domain] = r;
    }

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      title: Row(
        children: [
          Expanded(
            child: Text(
              AppLocalizations.of(context).get(S.selectNetwork),
              style: const TextStyle(fontSize: 18),
            ),
          ),
          // Progress / count badge
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: speedState.testing
                ? Row(
                    key: const ValueKey('testing'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LoadingWidget.inline(
                        value: speedState.results.isEmpty
                            ? null
                            : speedState.testedCount /
                                  speedState.results.length,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${speedState.testedCount}/${speedState.results.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  )
                : Text(
                    key: const ValueKey('done'),
                    '${speedState.onlineCount}/${speedState.results.length} ✓',
                    style: TextStyle(
                      fontSize: 12,
                      color: speedState.onlineCount > 0
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.55,
        child: ListView.builder(
          itemCount: speedState.results.length + 1, // +1 for custom
          itemBuilder: (context, index) {
            if (index < speedState.results.length) {
              final result = speedState.results[index];
              // Find the original index in the domain list for "Line N" label
              final lineIndex = domains.indexOf(result.domain);
              final lineLabel = lineIndex >= 0
                  ? 'Line ${lineIndex + 1}'
                  : result.domain;
              return _buildDomainTile(
                context,
                ref,
                result,
                lineLabel,
                currentDomain,
              );
            }
            // Last item: custom domain
            return _buildCustomTile(context, ref, currentDomain, domains);
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: speedState.testing
              ? null
              : () => ref.read(speedTestProvider.notifier).runTest(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.speed,
                size: 16,
                color: speedState.testing ? Colors.grey : null,
              ),
              const SizedBox(width: 4),
              Text(AppLocalizations.of(context).get(S.retest)),
            ],
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context).get(S.close)),
        ),
      ],
    );
  }

  Widget _buildDomainTile(
    BuildContext context,
    WidgetRef ref,
    DomainTestResult result,
    String label,
    String currentDomain,
  ) {
    final isSelected = result.domain == currentDomain;
    final latency = result.latencyMs;
    final status = domainLatencyStatus(latency);

    // Status indicator
    Widget trailing;
    if (status == DomainLatencyStatus.untested) {
      trailing = const LoadingWidget.inline();
    } else if (status == DomainLatencyStatus.unavailable) {
      trailing = Icon(Icons.close, size: 16, color: Theme.of(context).colorScheme.error);
    } else {
      final latColor = status == DomainLatencyStatus.normal
          ? AppColors.success
          : AppColors.warning;
      trailing = Text(
        '${latency!}ms',
        style: TextStyle(
          fontSize: 12,
          color: latColor,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -2),
      leading: isSelected
          ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary, size: 20)
          : const Icon(Icons.circle_outlined, size: 20, color: Colors.grey),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
          color: isSelected ? Theme.of(context).colorScheme.primary : null,
        ),
      ),
      trailing: trailing,
      onTap: () {
        ref.read(domainProvider.notifier).setDomain(result.domain);
        Navigator.pop(context);
      },
    );
  }

  Widget _buildCustomTile(
    BuildContext context,
    WidgetRef ref,
    String currentDomain,
    List<String> domains,
  ) {
    final isCustom = !domains.contains(currentDomain);

    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -2),
      leading: isCustom
          ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary, size: 20)
          : const Icon(Icons.edit_outlined, size: 20, color: Colors.grey),
      title: Text(
        isCustom
            ? (AppLocalizations.of(context).get(S.customLine))
            : (AppLocalizations.of(context).get(S.customLineEllipsis)),
        style: TextStyle(
          fontSize: 14,
          fontWeight: isCustom ? FontWeight.w700 : FontWeight.normal,
          color: isCustom ? Theme.of(context).colorScheme.primary : Colors.grey,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => _showCustomDomainDialog(context, ref),
    );
  }

  void _showCustomDomainDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();

    final dialog = showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).get(S.customLineDialogTitle)),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context).get(S.domainUrl),
            hintText: 'e.g., example.com',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context).get(S.cancel)),
          ),
          ElevatedButton(
            onPressed: () {
              final raw = DomainNotifier.normalizeCustomDomain(
                controller.text,
              );
              if (raw.isEmpty) return;
              final l = AppLocalizations.of(context);
              if (!DomainNotifier.isValidCustomDomain(raw)) {
                showAppSnack(context, l.get(S.customDomainInvalid));
                return;
              }
              if (DomainNotifier.isBuiltInDomain(raw)) {
                ref.read(domainProvider.notifier).setCustomDomain(raw);
                Navigator.pop(context);
                return;
              }
              // Non-built-in domain: warn first. The saved session is
              // NOT auto-sent there; the user logs in again afterwards.
              showDialog(
                context: context,
                builder: (warnCtx) => AlertDialog(
                  title: Text(l.get(S.customDomainWarningTitle)),
                  content: Text(l.get(S.customDomainWarningBody)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(warnCtx),
                      child: Text(AppLocalizations.of(context).get(S.cancel)),
                    ),
                    FilledButton(
                      onPressed: () {
                        ref
                            .read(domainProvider.notifier)
                            .setCustomDomain(raw);
                        Navigator.pop(warnCtx);
                        Navigator.pop(context);
                        showAppSnack(context,
                              l.get(S.customDomainReloginHint),
                            );
                      },
                      child: Text(l.get(S.customDomainSwitchAnyway)),
                    ),
                  ],
                ),
              );
            },
            child: Text(AppLocalizations.of(context).get(S.save)),
          ),
        ],
      ),
    );
    // Release the controller once the dialog's exit animation is done.
    dialog.whenComplete(
      () => Future<void>.delayed(
        const Duration(milliseconds: 400),
        controller.dispose,
      ),
    );
  }
}
