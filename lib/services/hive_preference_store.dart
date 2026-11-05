// Hive-backed PreferenceStore for the ported external book sources
// (Anna's Archive / LibGen, from warreth/OpenlibExtended).
//
// OpenlibExtended's InstanceManager used DbPreferenceStore (sqflite); olib
// lite has no sqflite, so the same PreferenceStore contract is backed by
// HiveService.settingsBox — the same box the app's own settings use.
// The keys InstanceManager/SlumCatalogue write are plain strings and bools,
// both storable in Hive.

// Project imports:
import 'package:zlibx/services/hive_service.dart';
import 'package:zlibx/services/preference_store.dart';

/// PreferenceStore backed by the app's Hive settings box.
class HivePreferenceStore implements PreferenceStore {
  @override
  Future<Object?> read(String key) async {
    return HiveService.settingsBox.get(key);
  }

  @override
  Future<void> write(String key, Object? value) async {
    if (value == null) {
      await HiveService.settingsBox.delete(key);
    } else {
      await HiveService.settingsBox.put(key, value);
    }
  }
}
