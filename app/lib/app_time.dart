import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'device/secure_store.dart';

/// App-local timezone handling.
///
/// All displayed times (scanner clock, admin screens, session timestamps)
/// convert through `DateTime.toLocal()` — so by pointing the Dart local
/// location at the ORG's IANA timezone, every screen shows business-local
/// time regardless of the device or server clock. The VPS system clock and
/// device clocks are never touched.
class AppTime {
  static bool _initialized = false;

  static Future<void> init() async {
    if (!_initialized) {
      tzdata.initializeTimeZones();
      _initialized = true;
    }
    // Apply the stored org timezone if we have one (set on handshake).
    final orgTz = await SecureStore.instance.getOrgTimezone();
    if (orgTz != null && orgTz.isNotEmpty) {
      setLocal(orgTz);
    }
  }

  /// Point "local" time at the org timezone.
  static void setLocal(String ianaName) {
    try {
      tz.setLocalLocation(tz.getLocation(ianaName));
    } catch (_) {
      // Unknown zone — keep whatever is set; display falls back to device local.
    }
  }
}
