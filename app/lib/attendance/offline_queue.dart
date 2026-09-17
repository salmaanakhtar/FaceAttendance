import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config.dart';
import '../device/api.dart';

class PendingScan {
  final String dedupeKey;
  final String employeeId;
  final DateTime deviceTime;
  final String? directionHint;
  final double? confidence;
  final double? livenessScore;
  final String? faceHash;
  int retries;

  PendingScan({
    required this.dedupeKey,
    required this.employeeId,
    required this.deviceTime,
    this.directionHint,
    this.confidence,
    this.livenessScore,
    this.faceHash,
    this.retries = 0,
  });

  Map<String, dynamic> toJson() => {
        'dedupeKey': dedupeKey,
        'employeeId': employeeId,
        'deviceTime': deviceTime.toUtc().toIso8601String(),
        'directionHint': directionHint,
        'confidence': confidence,
        'livenessScore': livenessScore,
        'faceHash': faceHash,
        'retries': retries,
      };

  static PendingScan fromJson(Map<String, dynamic> j) => PendingScan(
        dedupeKey: j['dedupeKey'] as String,
        employeeId: j['employeeId'] as String,
        deviceTime: DateTime.parse(j['deviceTime'] as String),
        directionHint: j['directionHint'] as String?,
        confidence: (j['confidence'] as num?)?.toDouble(),
        livenessScore: (j['livenessScore'] as num?)?.toDouble(),
        faceHash: j['faceHash'] as String?,
        retries: (j['retries'] as num?)?.toInt() ?? 0,
      );
}

/// Ensures concurrent callers share the same delivery for one idempotency key.
class ScanDeliveryGate {
  final Map<String, Future<Map<String, dynamic>>> _active = {};

  Future<Map<String, dynamic>> run(
    String key,
    Future<Map<String, dynamic>> Function() request,
  ) {
    final active = _active[key];
    if (active != null) return active;

    late final Future<Map<String, dynamic>> delivery;
    delivery = request().whenComplete(() {
      if (identical(_active[key], delivery)) _active.remove(key);
    });
    _active[key] = delivery;
    return delivery;
  }
}

/// Offline-first queue: every scan event is enqueued locally with a UUID
/// dedupe key, then flushed. Server-side unique constraint makes replays
/// idempotent.
class OfflineQueue extends ChangeNotifier {
  OfflineQueue._();
  @visibleForTesting
  OfflineQueue.forTesting(Box<String> box, this._sender) : _box = box;
  Future<Map<String, dynamic>> Function(PendingScan scan)? _sender;
  static final OfflineQueue instance = OfflineQueue._();

  static const _boxName = 'pending_scans';
  Box<String>? _box;
  bool _flushing = false;
  bool _online = true;
  Timer? _retryTimer;
  final ScanDeliveryGate _deliveryGate = ScanDeliveryGate();
  final _uuid = const Uuid();

  int get pendingCount => _box?.values.length ?? 0;
  bool get online => _online;
  void setOnline(bool value) {
    _online = value;
    notifyListeners();
    if (value) flush();
  }

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(kQueueFlushInterval, (_) {
      if (_online && pendingCount > 0) flush();
    });
    notifyListeners();
  }

  PendingScan? _pendingForEmployee(
      String employeeId, String? directionHint) {
    PendingScan? latest;
    for (final raw in _box?.values ?? const Iterable<String>.empty()) {
      try {
        final scan =
            PendingScan.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (scan.employeeId == employeeId &&
            scan.directionHint == directionHint &&
            (latest == null || scan.deviceTime.isAfter(latest.deviceTime))) {
          latest = scan;
        }
      } catch (_) {
        // Preserve unreadable records for recovery.
      }
    }
    return latest;
  }

  /// Enqueue (and try to deliver immediately).
  Future<Map<String, dynamic>> enqueue({
    required String employeeId,
    DateTime? deviceTime,
    String? directionHint,
    double? confidence,
    double? livenessScore,
    String? faceHash,
  }) async {
    // If this worker's prior request timed out, retry that exact idempotency
    // key instead of creating a second event that the server rejects via the
    // minimum-interval guard.
    final existing = _pendingForEmployee(employeeId, directionHint);
    if (existing != null) {
      if (_online) {
        try {
          return await _deliver(existing, offline: true);
        } on OfflineException {
          // Keep the original record queued.
        }
      }
      return {
        'queued': true,
        'pendingCount': pendingCount,
        'action': existing.directionHint == 'out' ? 'check_out' : 'check_in',
        'scanTime': existing.deviceTime.toUtc().toIso8601String(),
      };
    }
    final scan = PendingScan(
      dedupeKey: _uuid.v4(),
      employeeId: employeeId,
      deviceTime: deviceTime ?? DateTime.now(),
      directionHint: directionHint,
      confidence: confidence,
      livenessScore: livenessScore,
      faceHash: faceHash,
    );
    await _box!.put(scan.dedupeKey, jsonEncode(scan.toJson()));
    notifyListeners();
    if (_online) {
      try {
        return await _deliver(scan);
      } on OfflineException {
        return {'queued': true, 'pendingCount': pendingCount};
      }
    }
    return {'queued': true, 'pendingCount': pendingCount};
  }

  Future<Map<String, dynamic>> _deliver(PendingScan scan,
      {bool offline = false}) {
    // A timer flush and a worker retry can happen at the same instant. Share
    // one request for a dedupe key so a failed parallel request cannot put a
    // record back after the successful request removed it.
    return _deliveryGate.run(
      scan.dedupeKey,
      () async {
        // Deliver this worker's earlier punches first, including when a new
        // foreground clock-out races the background flush of their clock-in.
        // Hive key iteration order is not guaranteed, so order explicitly by
        // the locally captured event time rather than the box's key order.
        final earlier = <PendingScan>[];
        for (final raw
            in _box?.values ?? const Iterable<String>.empty()) {
          try {
            final previous =
                PendingScan.fromJson(jsonDecode(raw) as Map<String, dynamic>);
            if (previous.dedupeKey != scan.dedupeKey &&
                previous.employeeId == scan.employeeId &&
                previous.deviceTime.isBefore(scan.deviceTime)) {
              earlier.add(previous);
            }
          } catch (_) {
            // Preserve unreadable records for recovery.
          }
        }
        earlier.sort((a, b) => a.deviceTime.compareTo(b.deviceTime));
        for (final previous in earlier) {
          await _deliver(previous, offline: true);
        }
        return _deliverOnce(scan, offline: offline);
      },
    );
  }

  Future<Map<String, dynamic>> _deliverOnce(PendingScan scan,
      {required bool offline}) async {
    final res = _sender != null
        ? await _sender!(scan)
        : await ApiClient.instance.ingestScan(
            dedupeKey: scan.dedupeKey,
            employeeId: scan.employeeId,
            deviceTime: scan.deviceTime,
            directionHint: scan.directionHint,
            confidence: scan.confidence,
            livenessScore: scan.livenessScore,
            faceHash: scan.faceHash,
            offline: offline,
          );
    await _box!.delete(scan.dedupeKey);
    notifyListeners();
    return res;
  }

  /// Try to deliver everything queued. Best effort; failures stay queued.
  Future<void> flush() async {
    if (_flushing || !_online || _box == null) return;
    _flushing = true;
    try {
      final keys = List<String>.of(_box!.keys.cast<String>());
      for (final key in keys) {
        final raw = _box!.get(key);
        if (raw == null) continue;
        try {
          final scan =
              PendingScan.fromJson(jsonDecode(raw) as Map<String, dynamic>);
          try {
            await _deliver(scan, offline: true);
          } on OfflineException {
            break; // still offline — stop trying
          } on ServerException {
            scan.retries++;
            await _box!.put(key, jsonEncode(scan.toJson()));
            break; // retain attendance and ordering until delivery succeeds
          }
        } catch (_) {
          break; // storage/auth failures must never delete an unsent punch
        }
      }
    } finally {
      _flushing = false;
    }
  }
}
