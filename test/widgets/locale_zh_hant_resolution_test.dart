// Verifies the GENERATED gen-l10n delegate resolves Traditional Chinese
// for device locales zh-TW / zh-HK / zh-MO.
//
// Background (assessment §3 R1): the old hand-written delegate maps
// zh + country TW/HK/MO to the zh_Hant table explicitly, and
// supportedLocales carries all 8 entries. The generated delegate's
// lookup is derived from the ARB files, so this is only guaranteed
// because the region ARB files exist (lib/l10n/app_zh_TW.arb,
// app_zh_HK.arb, app_zh_MO.arb — byte-copies of the zh_Hant
// content). If those files are ever removed, this test documents the
// failure mode: a Traditional user on TW/HK/MO would silently get
// Simplified instead.
//
// 'settings' is used as the probe because its zh value ('设置') and
// zh_Hant value ('設定') differ; 'cancel' would not discriminate
// (identical in both).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zlibx/l10n/generated/app_localizations.dart' as gen;

void main() {
  group('generated delegate resolves Traditional Chinese', () {
    for (final country in <String>['TW', 'HK', 'MO']) {
      testWidgets('zh-$country resolves to Traditional', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale('zh', country),
            supportedLocales: gen.AppLocalizations.supportedLocales,
            localizationsDelegates: const [gen.AppLocalizations.delegate],
            home: Builder(
              builder: (context) =>
                  Text(gen.AppLocalizations.of(context)!.settings),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('設定'), findsOneWidget);
      });
    }
  });
}
