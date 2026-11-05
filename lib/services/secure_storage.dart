import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Single place for secrets at rest.
///
/// Android: Keystore-backed AES (encryptedSharedPreferences). Anything that
/// can log its owner in — account session keys, backend bearer tokens —
/// belongs here, NEVER in the plaintext Hive boxes. Non-secret state
/// (settings, caches, download history) stays in Hive.
class SecureStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<String?> read(String key) => _storage.read(key: key);

  static Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  static Future<void> delete(String key) => _storage.delete(key: key);
}
