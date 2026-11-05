// Ported from warreth/OpenlibExtended (AGPL-3.0) — Anna's Archive / LibGen
// book sources. Original file: lib/services/preference_store.dart
// zlibx is AGPL-3.0 (see LICENSE); upstream MIT attribution for
// shiyi-0x7f/olib-mobile is preserved in LICENSE.

/// The little bit of key/value storage the mirror layer needs.
///
/// Pulling this behind an interface keeps [InstanceManager] and the
/// open-slum.org catalogue free of the app's sqlite singleton: the app
/// uses [DbPreferenceStore], tests use [MemoryPreferenceStore], and the
/// mirror rules can be exercised without a database at all.
abstract class PreferenceStore {
  Future<Object?> read(String key);
  Future<void> write(String key, Object? value);
}

/// In-memory store for tests and for a first run before the database is
/// ready.
class MemoryPreferenceStore implements PreferenceStore {
  final Map<String, Object?> _values = {};

  @override
  Future<Object?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, Object? value) async {
    _values[key] = value;
  }

  /// Test helper: what does the store currently hold?
  Map<String, Object?> get snapshot => Map.unmodifiable(_values);
}
