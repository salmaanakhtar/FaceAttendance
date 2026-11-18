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
  final int sequence;
  final String? directionHint;
  final double? confidence;
  final double? livenessScore;
  final String? faceHash;
  int retries;

  PendingScan({
    required this.dedupeKey,
    required this.employeeId,
    required this.deviceTime,
    this.sequence = 0,
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
        'sequence': sequence,
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
        sequence: (j['sequence'] as num?)?.toInt() ?? 0,
        directionHint: j['directionHint'] as String?,
        confidence: (j['confidence'] as num?)?.toDouble(),
        livenessScore: (j['livenessScore'] as num?)?.toDouble(),
        faceHash: j['faceHash'] as String?,
        retries: (j['retries'] as num?)?.toInt() ?? 0,
      );
}

int _comparePendingScans(PendingScan a, PendingScan b) {
  final time = a.deviceTime.compareTo(b.deviceTime);
  if (time != 0) return time;
  final order = a.sequence.compareTo(b.sequence);
  return order != 0 ? order : a.dedupeKey.compareTo(b.dedupeKey);
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
  bool _disposed = false;
  int _sequence = 0;
  final ScanDeliveryGate _deliveryGate = ScanDeliveryGate();
  final _uuid = const Uuid();

  DateTime? lastDeliveredAt;
  String? deliveryError;
  bool get syncing => _flushing;

  int get pendingCount => _box?.values.length ?? 0;
  bool get online => _online;
  Future<void> setOnline(bool value) async {
    _online = value;
    notifyListeners();
    if (value) await flush();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    super.dispose();
  }

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(kQueueFlushInterval, (_) {
      if (_online && pendingCount > 0) flush();
    });
    notifyListeners();
  }

  PendingScan? _pendingForEmployee(String employeeId, String? directionHint) {
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
    // Persist a tie-breaker: some device clocks give consecutive punches
    // identical timestamps. UUID/Hive key order cannot establish arrival order.
    for (final raw in _box!.values) {
      try {
        final saved =
            PendingScan.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (saved.sequence > _sequence) _sequence = saved.sequence;
      } catch (_) {
        // Preserve unreadable records for recovery.
      }
    }
    final scan = PendingScan(
      dedupeKey: _uuid.v4(),
      employeeId: employeeId,
      deviceTime: deviceTime ?? DateTime.now(),
      sequence: ++_sequence,
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
        for (final raw in _box?.values ?? const Iterable<String>.empty()) {
          try {
            final previous =
                PendingScan.fromJson(jsonDecode(raw) as Map<String, dynamic>);
            if (previous.dedupeKey != scan.dedupeKey &&
                previous.employeeId == scan.employeeId &&
                _comparePendingScans(previous, scan) < 0) {
              earlier.add(previous);
            }
          } catch (_) {
            // Preserve unreadable records for recovery.
          }
        }
        earlier.sort(_comparePendingScans);
        for (final previous in earlier) {
          await _deliver(previous, offline: true);
        }
        return _deliverOnce(scan, offline: offline);
      },
    );
  }

  Future<Map<String, dynamic>> _deliverOnce(PendingScan scan,
      {required bool offline}) async {
    late final Map<String, dynamic> res;
    try {
      res = _sender != null
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
    } on OfflineException {
      deliveryError =
          'Server unreachable. Saved punches will retry automatically.';
      notifyListeners();
      rethrow;
    } on ServerException catch (error) {
      deliveryError = error.status == 401 || error.status == 403
          ? 'Device access needs attention. Ask your manager to check device setup.'
          : 'Server could not accept a punch. It remains saved for retry.';
      notifyListeners();
      rethrow;
    }
    await _box!.delete(scan.dedupeKey);
    lastDeliveredAt = DateTime.now();
    deliveryError = null;
    notifyListeners();
    return res;
  }

  /// Try to deliver everything queued. Best effort; failures stay queued.
  Future<void> flush() async {
    if (_flushing || !_online || _box == null) return;
    _flushing = true;
    notifyListeners();
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
          deliveryError ??=
              'A saved punch needs attention. Contact your manager.';
          break; // storage/auth failures must never delete an unsent punch
        }
      }
    } finally {
      _flushing = false;
      notifyListeners();
    }
  }
}
