import 'dart:convert';
import 'dart:typed_data';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:encrypt/encrypt.dart' as enc;

import '../config.dart';
import '../device/api.dart';
import '../device/secure_store.dart';

class StoredTemplate {
  final String employeeId;
  final String name;
  final String employeeCode;
  final List<double> embedding;

  StoredTemplate({
    required this.employeeId,
    required this.name,
    required this.employeeCode,
    required this.embedding,
  });

  Map<String, dynamic> toJson() => {
        'employeeId': employeeId,
        'name': name,
        'employeeCode': employeeCode,
        'embedding': embedding,
      };

  factory StoredTemplate.fromJson(Map<String, dynamic> j) => StoredTemplate(
        employeeId: j['employeeId'] as String,
        name: j['name'] as String,
        employeeCode: j['employeeCode'] as String,
        embedding: (j['embedding'] as List).cast<num>().map((e) => e.toDouble()).toList(),
      );
}

/// Local template store: encrypted at rest (AES via secure-storage key),
/// synced from the server. Deterministic and safe to read on every frame.
class TemplateStore {
  TemplateStore._();
  static final TemplateStore instance = TemplateStore._();

  static const _boxName = 'templates';
  Box<String>? _box;
  Map<String, List<double>> _templates = {};
  Map<String, StoredTemplate> _meta = {};
  bool _loaded = false;

  bool get loaded => _loaded;
  int get count => _templates.length;
  Map<String, List<double>> get all => _templates;
  String? lastSyncError;

  /// Force a template resync and return its outcome (for UI feedback).
  /// Errors include the stack trace so failures are diagnosable on-device.
  Future<String> resync() async {
    try {
      await syncFromServer();
      lastSyncError = null;
      return 'ok:${_templates.length} templates';
    } catch (e, st) {
      lastSyncError = '$e\n$st';
      return 'failed: $e';
    }
  }

  Future<void> init() async {
    await SecureStore.instance.ensureTemplateKey();
    _box = await Hive.openBox<String>(_boxName);
    _templates = {};
    _meta = {};
    final raw = _box!.get('bundle');
    if (raw != null) {
      try {
        final json = jsonDecode(_decrypt(raw)) as List<dynamic>;
        for (final item in json) {
          final t = StoredTemplate.fromJson(item as Map<String, dynamic>);
          _templates[t.employeeId] = t.embedding;
          _meta[t.employeeId] = t;
        }
      } catch (_) {
        // corrupted bundle — ignore; next sync replaces it
      }
    }
    _loaded = true;
  }

  StoredTemplate? byId(String id) => _meta[id];
  /// Replace the local bundle from the server. Delta-aware on the server
  /// side is future work; for now replace atomically.
  /// The in-memory matcher is updated BEFORE persistence so a storage
  /// failure can never break live scanning.
  Future<void> syncFromServer() async {
    final res = await ApiClient.instance.fetchTemplates();
    final templates = (res['templates'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final list = <StoredTemplate>[];
    for (final t in templates) {
      final emb = t['embedding'];
      if (emb == null) continue;
      list.add(StoredTemplate(
        employeeId: t['employeeId'] as String,
        name: t['name'] as String,
        employeeCode: t['employeeCode'] as String,
        embedding: (emb as List).cast<num>().map((e) => e.toDouble()).toList(),
      ));
    }
    _templates = {for (final t in list) t.employeeId: t.embedding};
    _meta = {for (final t in list) t.employeeId: t};
    try {
      final json = jsonEncode(list.map((t) => t.toJson()).toList());
      await _box!.put('bundle', _encrypt(json));
    } catch (e, st) {
      // Persistence failure must not break the live matcher.
      lastSyncError = 'persist: $e\n$st';
      rethrow;
    }
  }

  /// AES-256 key from a 64-hex-char secret (32 bytes).
  static enc.Key aesKeyFromHex(String hex) {
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return enc.Key(bytes);
  }

  static enc.Key _aesKey() => aesKeyFromHex(SecureStore.instance.templateKeySync());

  String _encrypt(String plain) {
    final key = _aesKey();
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(key));
    final ct = encrypter.encrypt(plain, iv: iv);
    return 'v1:${iv.base64}:${ct.base64}';
  }

  String _decrypt(String data) {
    final parts = data.split(':');
    if (parts.length != 3 || parts[0] != 'v1') throw const FormatException('bad bundle');
    final key = _aesKey();
    final iv = enc.IV.fromBase64(parts[1]);
    final encrypter = enc.Encrypter(enc.AES(key));
    return encrypter.decrypt64(parts[2], iv: iv);
  }

  Future<void> dispose() async {
    await _box?.close();
  }
}

/// Local per-employee status cache: last direction + known in/out state,
/// used to pick the direction hint. Server remains authoritative.
class StatusCache {
  StatusCache._();
  static final StatusCache instance = StatusCache._();

  static const _boxName = 'status_cache';
  Box<String>? _box;
  final Map<String, String> _lastDirection = {};
  final Map<String, bool> _isIn = {};
  final Map<String, String> _lastAt = {};

  Future<void> init() async {
    await SecureStore.instance.ensureTemplateKey();
    _box = await Hive.openBox<String>(_boxName);
    for (final key in _box!.keys) {
      final parts = (key as String).split(':');
      if (parts.length != 2) continue;
      final emp = parts[0];
      final field = parts[1];
      final value = _box!.get(key) ?? '';
      if (field == 'direction') _lastDirection[emp] = value;
      if (field == 'isIn') _isIn[emp] = value == 'true';
      if (field == 'at') _lastAt[emp] = value;
    }
  }

  String? lastDirection(String employeeId) => _lastDirection[employeeId];
  bool? isIn(String employeeId) => _isIn[employeeId];

  void recordOutcome(String employeeId, String action, DateTime at) {
    if (action == 'check_in') {
      _lastDirection[employeeId] = 'in';
      _isIn[employeeId] = true;
    } else if (action == 'check_out') {
      _lastDirection[employeeId] = 'out';
      _isIn[employeeId] = false;
    }
    _lastAt[employeeId] = at.toIso8601String();
    _box?.put('$employeeId:direction', _lastDirection[employeeId]!);
    _box?.put('$employeeId:isIn', '${_isIn[employeeId]}');
    _box?.put('$employeeId:at', at.toIso8601String());
  }

  /// Reset all employees to "not checked in" (rollover hint correction).
  Future<void> markAllOut() async {
    for (final emp in _isIn.keys) {
      _isIn[emp] = false;
      _box?.put('$emp:isIn', 'false');
    }
  }
}

void schedulePeriodicTemplateSync() {
  Future<void> once() async {
    try {
      await TemplateStore.instance.syncFromServer();
    } catch (e) {
      TemplateStore.instance.lastSyncError ??= 'periodic: $e';
    }
  }

  Future<void> loop() async {
    while (true) {
      // Retry fast while the store is empty (broken sync self-heals).
      final delay = TemplateStore.instance.count == 0
          ? const Duration(seconds: 30)
          : kTemplateSyncInterval;
      await Future<void>.delayed(delay);
      await once();
    }
  }

  once();
  loop();
}
