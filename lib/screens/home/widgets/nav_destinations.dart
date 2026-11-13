import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../widgets/liquid_nav_bar.dart' show LiquidNavDestination;

/// The four top-level destinations, shared by the phone's bottom bar and the
/// tablet's navigation rail so the two can never drift apart.
List<LiquidNavDestination> homeDestinations(BuildContext context) {
  final t = AppLocalizations.of(context)!;
  return <LiquidNavDestination>[
    LiquidNavDestination(
      icon: Icons.local_fire_department_outlined,
      selectedIcon: Icons.local_fire_department,
      label: t.recommended,
    ),
    LiquidNavDestination(
      icon: Icons.cloud_download_outlined,
      selectedIcon: Icons.cloud_download,
      label: t.downloads,
    ),
    LiquidNavDestination(
      icon: Icons.person_outlined,
      selectedIcon: Icons.person,
      label: t.account,
    ),
    LiquidNavDestination(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: t.settings,
    ),
  ];
}
