import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:zlibx/services/hive_service.dart';
import 'package:zlibx/services/mirror_trust.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('mirror_trust');
    Hive.init(tempDir.path);
    await Hive.openBox(HiveService.settingsBoxName);
  });
  setUp(() => Hive.box(HiveService.settingsBoxName).clear());
  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('built-in community mirror needs confirmation, then is remembered',
      () async {
    // luto.top is a built-in mirror but NOT a Z-Library family host,
    // so it prompts. (bookroom.lifestyle is a family host and never
    // prompts — see the next test.)
    expect(MirrorTrust.isConfirmed('luto.top', builtIn: true), isFalse);
    await MirrorTrust.confirm('Luto.Top:443');
    expect(MirrorTrust.isConfirmed('luto.top', builtIn: true), isTrue);
    expect(MirrorTrust.isConfirmed('other-mirror.example', builtIn: true),
        isFalse);
  });

  test('family hosts and user-typed custom lines never prompt', () {
    expect(MirrorTrust.isConfirmed('z-lib.fm', builtIn: true), isTrue);
    // The default line is a family host: no prompt, even on a fresh
    // install.
    expect(MirrorTrust.isConfirmed('bookroom.lifestyle', builtIn: true),
        isTrue);
    expect(MirrorTrust.isConfirmed('z-library.im', builtIn: true), isTrue);
    expect(MirrorTrust.isConfirmed('reader.z-lib.fm', builtIn: true),
        isTrue);
    expect(MirrorTrust.isConfirmed('my.own.host', builtIn: false), isTrue);
  });

  test('existing install is grandfathered, fresh install is not', () async {
    final box = Hive.box(HiveService.settingsBoxName);
    await box.put('domain', 'luto.top');
    await MirrorTrust.grandfatherCurrent();
    expect(MirrorTrust.isConfirmed('luto.top', builtIn: true), isTrue);

    await box.clear(); // fresh install: no saved domain
    await MirrorTrust.grandfatherCurrent();
    expect(MirrorTrust.isConfirmed('luto.top', builtIn: true), isFalse);
    // …but a family host still never prompts on a fresh install.
    expect(MirrorTrust.isConfirmed('bookroom.lifestyle', builtIn: true),
        isTrue);
  });
}
