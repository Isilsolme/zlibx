import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zlibx/models/nav_label_mode.dart';
import 'package:zlibx/providers/settings_provider.dart';
import 'package:zlibx/widgets/app_nav_rail.dart';
import 'package:zlibx/widgets/liquid_nav_bar.dart';

const _destinations = <LiquidNavDestination>[
  LiquidNavDestination(
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    label: 'Home',
  ),
  LiquidNavDestination(
    icon: Icons.download_outlined,
    selectedIcon: Icons.download,
    label: 'Downloads',
  ),
  LiquidNavDestination(
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
    label: 'Account',
  ),
  LiquidNavDestination(
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    label: 'Settings',
  ),
];

/// Avoids touching Hive: the real notifier reads the settings box.
class _StubLabelMode extends NavLabelModeNotifier {
  _StubLabelMode(this._mode);

  final NavLabelMode _mode;

  @override
  NavLabelMode build() => _mode;
}

Widget _harness({
  required int selected,
  required ValueChanged<int> onSelected,
  NavLabelMode labelMode = NavLabelMode.always,
}) {
  return ProviderScope(
    overrides: [
      navLabelModeProvider.overrideWith(() => _StubLabelMode(labelMode)),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            AppNavRail(
              destinations: _destinations,
              selectedIndex: selected,
              onSelected: onSelected,
            ),
            const Expanded(child: SizedBox.expand()),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders an opaque rail and reports taps', (tester) async {
    var selected = -1;
    await tester.pumpWidget(
      _harness(selected: 0, onSelected: (i) => selected = i),
    );

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Downloads'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    // No liquid-glass bar on tablet widths.
    expect(find.byType(LiquidNavBar), findsNothing);

    await tester.tap(find.text('Downloads'));
    await tester.pump();
    expect(selected, 1);
  });

  testWidgets('labels follow the navigation label mode', (tester) async {
    await tester.pumpWidget(
      _harness(selected: 0, onSelected: (_) {}, labelMode: NavLabelMode.never),
    );
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.labelType, NavigationRailLabelType.none);
    // Every destination is still reachable/announced even without labels.
    expect(rail.destinations, hasLength(4));
  });

  testWidgets('auto label mode only labels the selected destination', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(selected: 1, onSelected: (_) {}, labelMode: NavLabelMode.auto),
    );
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.labelType, NavigationRailLabelType.selected);
  });
}
