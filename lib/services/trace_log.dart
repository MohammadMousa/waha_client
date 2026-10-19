import 'package:flutter/foundation.dart';

import 'local_prefs.dart';

/// Lightweight event log for debugging, kept API-compatible with the kiosk
/// app's TraceLog so call sites across the app (invoice flow, landing page
/// refresh, etc.) didn't need to change. waha_client has no native
/// diagnostic pipeline to write into (no device-local file, no kiosk
/// support team reading it off a tablet), so this just prints to the
/// console/devtools instead of crossing a platform channel.
///
/// Gated by [LocalPrefs.effectiveLoggingEnabled], same as the kiosk app,
/// so a server-side `enable_logging` property still has an effect in the
/// browser/adb console.
class TraceLog {
  static Future<void> log(String label) async {
    if (!LocalPrefs.effectiveLoggingEnabled) return;
    debugPrint('[trace] $label');
  }

  /// No native side to push the effective flag to — kept as a no-op so
  /// call sites (main.dart, Settings) don't need special-casing.
  static Future<void> applyEffective() async {}

  static Future<void> applyRemoteConfig(Map<String, String> config) async {
    if (config.isEmpty) return;
    final on = config['enable_logging']?.trim().toLowerCase() == 'true';
    if (LocalPrefs.remoteLoggingEnabled != on) {
      await LocalPrefs.setRemoteLoggingEnabled(on);
    }
  }

  static Future<void> setEnabled(bool enabled) async {
    await LocalPrefs.setLoggingEnabled(enabled);
  }
}
