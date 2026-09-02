import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device-scoped secrets: provisioning key, tokens, org identity.
/// All backed by Android Keystore.
class SecureStore {
  SecureStore._();
  static final SecureStore instance = SecureStore._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> setDeviceKey(String key) =>
      _storage.write(key: 'device_key', value: key);
  Future<String?> getDeviceKey() => _storage.read(key: 'device_key');
  Future<void> setDeviceToken(String token) =>
      _storage.write(key: 'device_token', value: token);
  Future<String?> getDeviceToken() => _storage.read(key: 'device_token');
  Future<void> setOrgId(String orgId) =>
      _storage.write(key: 'org_id', value: orgId);
  Future<String?> getOrgId() => _storage.read(key: 'org_id');
  Future<void> setSiteId(String siteId) =>
      _storage.write(key: 'site_id', value: siteId);
  Future<String?> getSiteId() => _storage.read(key: 'site_id');
  Future<void> setDeviceId(String deviceId) =>
      _storage.write(key: 'device_id', value: deviceId);
  Future<String?> getDeviceId() => _storage.read(key: 'device_id');
  Future<void> setOrgName(String name) =>
      _storage.write(key: 'org_name', value: name);
  Future<String?> getOrgName() => _storage.read(key: 'org_name');
  Future<void> setOrgTimezone(String tz) =>
      _storage.write(key: 'org_timezone', value: tz);
  Future<String?> getOrgTimezone() => _storage.read(key: 'org_timezone');
  Future<void> setKioskRoster(String roster) =>
      _storage.write(key: 'kiosk_roster', value: roster);
  Future<String?> getKioskRoster() => _storage.read(key: 'kiosk_roster');

  Future<void> setAdminRefreshToken(String token) =>
      _storage.write(key: 'admin_refresh', value: token);
  Future<String?> getAdminRefreshToken() => _storage.read(key: 'admin_refresh');
  Future<void> clearAdminTokens() => _storage.delete(key: 'admin_refresh');

  Future<void> setInstalledVersion(String v) =>
      _storage.write(key: 'installed_version', value: v);
  Future<String?> getInstalledVersion() =>
      _storage.read(key: 'installed_version');

  /// Wipe every credential/secret (device key, tokens, org data, admin
  /// session, template key). Used once when a new build ships a storage
  /// reset so no stale data can survive across deployments.
  Future<void> clearAll() async {
    for (final key in [
      'device_key',
      'device_token',
      'org_id',
      'org_name',
      'org_timezone',
      'site_id',
      'device_id',
      'admin_refresh',
      'template_key',
      'kiosk_roster',
    ]) {
      await _storage.delete(key: key);
    }
    _templateKeyCache = null;
  }

  String? _templateKeyCache;

  /// Ensure the template encryption key is materialized in memory.
  Future<void> ensureTemplateKey() async {
    if (_templateKeyCache != null) return;
    _templateKeyCache = await _loadOrCreateTemplateKey();
  }

  /// Synchronous accessor — call [ensureTemplateKey] first.
  String templateKeySync() {
    final k = _templateKeyCache;
    if (k == null) throw StateError('templateKey not loaded');
    return k;
  }

  Future<String> _loadOrCreateTemplateKey() async {
    final existing = await _storage.read(key: 'template_key');
    if (existing != null) return existing;
    final key = _randomHex(32);
    await _storage.write(key: 'template_key', value: key);
    return key;
  }

  static String _randomHex(int bytes) {
    final rng = Random.secure();
    return List.generate(
            bytes, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
