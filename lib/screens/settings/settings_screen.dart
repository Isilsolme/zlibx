import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/gradient_app_bar.dart';
import '../../widgets/update_dialog.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/locale_utils.dart' as locale_utils;
import '../auth/login_screen.dart';
import 'widgets/download_path_section.dart';
import 'widgets/donation_key_section.dart';
import 'widgets/about_section.dart';
import 'widgets/language_section.dart';
import 'widgets/theme_section.dart';
import 'widgets/network_section.dart';
import 'widgets/section_header.dart';
import 'widgets/settings_card.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final t = AppLocalizations.of(context);
    final isZh = locale_utils.isZhLocale(context);

    return Scaffold(
      appBar: GradientAppBar(title: t.get('settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // Signed in: the profile card lives on the account page now.
          // Signed out (e.g. skipped login): offer the login screen
          // here — otherwise there is no in-app way back to login.
          if (user == null)
            SettingsCard(
              child: ListTile(
                leading: const Icon(Icons.login),
                title: Text(t.get('login')),
                subtitle: Text(t.get('login_to_continue')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => const LoginScreen(),
                  ),
                ),
              ),
            ),
          if (user == null) const SizedBox(height: 24),

          // ── Library ──────────────────────────────────────────────
          SectionHeader(icon: Icons.menu_book_rounded, title: t.get('library')),
          const DownloadPathSection(),
          const DonationKeySection(),

          const SizedBox(height: 20),

          // ── Network ─────────────────────────────────────────────
          const NetworkSection(),

          const SizedBox(height: 20),

          // ── Theme ────────────────────────────────────────────────
          const ThemeSection(),

          const SizedBox(height: 20),

          // ── Update ───────────────────────────────────────────────
          SectionHeader(
            icon: Icons.system_update_rounded,
            title: isZh ? '更新' : 'Update',
          ),
          SettingsCard(
            child: ListTile(
              leading: const Icon(Icons.system_update),
              title: Text(isZh ? '检查更新' : 'Check for Updates'),
              subtitle: FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snapshot) {
                  final version = snapshot.data?.version ?? '...';
                  return Text(
                    isZh ? '当前版本: v$version' : 'Current version: v$version',
                  );
                },
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showManualUpdateCheck(context),
            ),
          ),

          const SizedBox(height: 20),

          // ── Language ─────────────────────────────────────────────
          const LanguageSection(),

          const SizedBox(height: 20),

          // ── About ────────────────────────────────────────────────
          const AboutSection(),
        ],
      ),
    );
  }
}
