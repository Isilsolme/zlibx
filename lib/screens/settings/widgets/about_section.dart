import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../l10n/app_localizations.dart';
import 'section_header.dart';
import 'settings_card.dart';
import '../../../widgets/settings_sheet.dart';

import '../../../l10n/s_keys.dart';

class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          icon: Icons.info_outline_rounded,
          title: AppLocalizations.of(context).get(S.about),
        ),
        SettingsCard(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(AppLocalizations.of(context).get(S.version)),
                trailing: FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) {
                    final version = snapshot.data?.version ?? '...';
                    return Text(version);
                  },
                ),
              ),
              const SettingsDivider(),
              ListTile(
                leading: const Icon(Icons.book_outlined),
                title: Text(AppLocalizations.of(context).get(S.aboutZlibrary)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showAboutApp(context),
              ),
              const SettingsDivider(),
              ListTile(
                leading: const Icon(Icons.code),
                title: Text(
                  AppLocalizations.of(context).get(S.githubOpenSource),
                ),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: () => _launchUrl('https://github.com/minglaiyo/zlibx'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showAboutApp(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context);

    showSettingsSheet(
      context,
      title: 'zlibx',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.auto_stories_rounded,
                    color: cs.onPrimaryContainer,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    t.get(S.aboutAiBuiltTitle),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              t.get(S.aboutBody),
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurfaceVariant,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              t.get(S.aboutCredits),
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurfaceVariant,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () =>
                        _launchUrl('https://github.com/shiyi-0x7f/olib-mobile'),
                    icon: const Icon(Icons.code, size: 16),
                    label: Text(t.get(S.original)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () =>
                        _launchUrl('https://github.com/minglaiyo/zlibx'),
                    icon: const Icon(Icons.code, size: 16),
                    label: const Text('zlibx'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, color: cs.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t.get(S.aboutQuote),
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: cs.onSurface,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
