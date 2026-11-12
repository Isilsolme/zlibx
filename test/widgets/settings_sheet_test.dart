import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zlibx/widgets/settings_sheet.dart';

void main() {
  testWidgets('settings sheet opens on screen with the shared rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showSettingsSheet(
                  context,
                  title: 'Settings title',
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SettingsOptionTile(
                        title: 'Option one',
                        selected: true,
                        onTap: () {},
                      ),
                      SettingsSwitchTile(
                        title: 'Switch one',
                        value: true,
                        onChanged: (_) {},
                      ),
                    ],
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Settings title'), findsOneWidget);
    expect(find.text('Option one'), findsOneWidget);
    expect(find.text('Switch one'), findsOneWidget);

    final rect = tester.getRect(find.text('Settings title'));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(
      rect.bottom,
      lessThanOrEqualTo(
        tester.view.physicalSize.height / tester.view.devicePixelRatio,
      ),
    );
  });
}
