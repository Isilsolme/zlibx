import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:zlibx/services/hive_service.dart';
import 'package:zlibx/services/storage_service.dart';

/// The local download-history blob:
/// * concurrent read-modify-write calls must not lose an entry (the
///   second writer used to start from a stale blob), and
/// * a corrupt blob must read as empty instead of throwing from
///   `as String` / `jsonDecode`, which used to break the whole
///   download-history path until the app was reinstalled.
void main() {
  late Directory tempDir;
  late StorageService storage;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('storage_service');
    Hive.init(tempDir.path);
    await Hive.openBox(HiveService.settingsBoxName);
  });

  setUp(() async {
    await Hive.box(HiveService.settingsBoxName).clear();
    storage = StorageService();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('concurrent addToDownloadHistory calls both survive', () async {
    await Future.wait([
      storage.addToDownloadHistory(
        '1',
        'Book One',
        'Author A',
        '/path/one.epub',
      ),
      storage.addToDownloadHistory(
        '2',
        'Book Two',
        'Author B',
        '/path/two.epub',
      ),
    ]);

    final history = await storage.getDownloadHistory();
    expect(history.keys, containsAll(<String>['1', '2']));
    expect(history['1']!['title'], 'Book One');
    expect(history['2']!['title'], 'Book Two');
  });

  test('concurrent add and remove end in a consistent blob', () async {
    await storage.addToDownloadHistory('1', 'Book One', null, '/one.epub');

    await Future.wait([
      storage.addToDownloadHistory('2', 'Book Two', null, '/two.epub'),
      storage.removeFromDownloadHistory('1'),
    ]);

    final history = await storage.getDownloadHistory();
    expect(history.containsKey('1'), isFalse);
    expect(history['2']!['title'], 'Book Two');
  });

  test('a corrupt JSON blob reads as empty instead of throwing', () async {
    await Hive.box(HiveService.settingsBoxName).put(
      'download_history',
      '{not json',
    );

    final history = await storage.getDownloadHistory();
    expect(history, isEmpty);
    // The bad value is preserved for inspection, never silently dropped.
    expect(
      Hive.box(HiveService.settingsBoxName).get('download_history_corrupt'),
      '{not json',
    );
  });

  test('a non-String blob reads as empty instead of throwing', () async {
    await Hive.box(HiveService.settingsBoxName).put(
      'download_history',
      <String, dynamic>{'1': 'not a blob'},
    );

    final history = await storage.getDownloadHistory();
    expect(history, isEmpty);
  });

  test('entries that are not maps are dropped', () async {
    await Hive.box(HiveService.settingsBoxName).put(
      'download_history',
      '{"1": {"title": "kept"}, "2": "not a map"}',
    );

    final history = await storage.getDownloadHistory();
    expect(history.keys, <String>['1']);
    expect(history['1']!['title'], 'kept');
  });

  test('addToDownloadHistory repairs a corrupt blob', () async {
    await Hive.box(HiveService.settingsBoxName).put(
      'download_history',
      'garbage',
    );

    await storage.addToDownloadHistory('9', 'Book Nine', null, '/nine.epub');

    final history = await storage.getDownloadHistory();
    expect(history.keys, <String>['9']);
  });
}
