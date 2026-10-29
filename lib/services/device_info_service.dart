import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// Phone/computer details sent with sign-in so the user's sessions list can
/// say which device each one is. The web build sends nothing: the server
/// reads the browser and system from the request itself.
class DeviceInfoService {
  static Map<String, String>? _cache;

  static Future<Map<String, String>> load() async {
    if (_cache != null) return _cache!;
    final info = <String, String>{};
    if (!kIsWeb) {
      try {
        final plugin = DeviceInfoPlugin();
        switch (defaultTargetPlatform) {
          case TargetPlatform.android:
            final a = await plugin.androidInfo;
            info['os'] = 'Android';
            info['osVersion'] = a.version.release;
            info['model'] = '${a.manufacturer} ${a.model}'.trim();
            break;
          case TargetPlatform.linux:
            final l = await plugin.linuxInfo;
            info['os'] = 'Linux';
            info['osVersion'] = l.versionId ?? l.version ?? '';
            info['model'] = l.prettyName;
            break;
          default:
            break;
        }
      } catch (_) {
        // Optional extra — never block a sign-in over it.
      }
    }
    info.removeWhere((_, v) => v.isEmpty);
    return _cache = info;
  }
}
