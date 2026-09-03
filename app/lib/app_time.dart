import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'device/secure_store.dart';

/// App-local timezone handling.
///
/// Displayed timestamps are converted through the organization's IANA
/// timezone. The live clock also uses the most recently measured difference
/// between the server and device clocks, because server time is authoritative
/// for attendance and a kiosk's Android clock may be misconfigured.
class AppTime {
  static bool _initialized = false;
  static DateTime? _serverUtcAtSync;
  static Stopwatch? _elapsedSinceServerSync;

  static Future<void> init() async {
    if (!_initialized) {
      tzdata.initializeTimeZones();
      _initialized = true;
    }
    // Apply the stored org timezone if we have one (set on handshake).
    final orgTz = await SecureStore.instance.getOrgTimezone();
    final orgName = await SecureStore.instance.getOrgName();
    if (orgTz != null && orgTz.isNotEmpty) {
      setLocal(orgTz, orgName: orgName);
    }
    // v1.2.9 persisted a raw device/server offset. It becomes wrong if the
    // Android clock is subsequently corrected, so discard it permanently.
    await SecureStore.instance.clearServerClockOffset();
  }

  /// Point "local" time at the org timezone.
  static String organizationTimezone(String ianaName, {String? orgName}) {
    // Early Yabil deployments were seeded with Pakistan's timezone. Keep the
    // kiosk correct even before the production database migration is run.
    if (orgName?.trim().toLowerCase() == 'yabil' &&
        ianaName == 'Asia/Karachi') {
      return 'Africa/Johannesburg';
    }
    return ianaName;
  }

  static void setLocal(String ianaName, {String? orgName}) {
    try {
      tz.setLocalLocation(
        tz.getLocation(organizationTimezone(ianaName, orgName: orgName)),
      );
    } catch (_) {
      // Unknown zone — keep the last valid location.
    }
  }

  /// Anchor the live clock directly to a server timestamp. A monotonic
  /// stopwatch advances it afterward, so Android wall-clock or timezone
  /// changes cannot be added a second time.
  static void syncServerTime(
    DateTime serverTime, {
    Duration roundTrip = Duration.zero,
  }) {
    _serverUtcAtSync = serverTime.toUtc().add(roundTrip ~/ 2);
    _elapsedSinceServerSync = Stopwatch()..start();
  }

  /// Current time in the organization's timezone, corrected against the
  /// latest server-time sample when one is available.
  static tz.TZDateTime now() {
    final serverUtc = _serverUtcAtSync;
    final elapsed = _elapsedSinceServerSync;
    final utcNow = serverUtc != null && elapsed != null
        ? serverUtc.add(elapsed.elapsed)
        : DateTime.now().toUtc();
    return tz.TZDateTime.from(utcNow, tz.local);
  }

  static void useDeviceClock() {
    _elapsedSinceServerSync?.stop();
    _elapsedSinceServerSync = null;
    _serverUtcAtSync = null;
  }
}
