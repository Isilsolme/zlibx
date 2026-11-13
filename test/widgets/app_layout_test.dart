import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zlibx/models/grid_columns_mode.dart';
import 'package:zlibx/theme/app_layout.dart';

void main() {
  group('AppLayout.gridColumns', () {
    test('auto fits the phone grid at the current 3-column density', () {
      // 411dp phone minus the 20dp page gutter each side.
      expect(AppLayout.gridColumns(GridColumnsMode.auto, 371), 3);
      // Very narrow phone: never below two columns.
      expect(AppLayout.gridColumns(GridColumnsMode.auto, 280), 2);
    });

    test('auto adds columns as the window grows', () {
      expect(AppLayout.gridColumns(GridColumnsMode.auto, 536), 4);
      expect(AppLayout.gridColumns(GridColumnsMode.auto, 736), 5);
      expect(AppLayout.gridColumns(GridColumnsMode.auto, 936), 7);
      expect(AppLayout.gridColumns(GridColumnsMode.auto, 1176), 8);
    });

    test('auto stops at the maximum on very wide windows', () {
      expect(AppLayout.gridColumns(GridColumnsMode.auto, 2400), 8);
    });

    test('manual modes ignore the width', () {
      expect(AppLayout.gridColumns(GridColumnsMode.two, 1200), 2);
      expect(AppLayout.gridColumns(GridColumnsMode.three, 1200), 3);
      expect(GridColumnsMode.auto.fixedColumns, isNull);
      expect(GridColumnsMode.two.fixedColumns, 2);
      expect(GridColumnsMode.three.fixedColumns, 3);
    });
  });

  test('page gutter widens with the window size class', () {
    expect(AppLayout.pageGutter(400), 20);
    expect(AppLayout.pageGutter(600), 32);
    expect(AppLayout.pageGutter(1239), 32);
    expect(AppLayout.pageGutter(1240), 48);
  });

  testWidgets('the rail replaces the bottom bar from 600dp', (tester) async {
    Future<bool> usesRailAt(double width) async {
      late bool usesRail;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: Size(width, 900)),
            child: Builder(
              builder: (context) {
                usesRail = AppLayout.usesNavRail(context);
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      return usesRail;
    }

    expect(await usesRailAt(599), isFalse);
    expect(await usesRailAt(600), isTrue);
    expect(await usesRailAt(1280), isTrue);
  });

  testWidgets('nav clearance drops once the rail is in use', (tester) async {
    Future<double> clearanceAt(double width) async {
      late double clearance;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 900),
              viewPadding: const EdgeInsets.only(bottom: 24),
            ),
            child: Builder(
              builder: (context) {
                clearance = AppLayout.navClearance(context);
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      return clearance;
    }

    // Phone: the floating bar's 96dp is reserved inside each scrollable.
    expect(await clearanceAt(411), 96);
    // Tablet: rail takes the width, so only 24dp + the system inset remain.
    expect(await clearanceAt(1024), 48);
  });
}
