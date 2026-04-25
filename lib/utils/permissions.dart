import 'package:flutter/foundation.dart';
import '../platform/app_platform.dart';

// ✅ Conditional import to prevent web compilation errors
import 'package:permission_handler/permission_handler.dart'
    if (dart.library.html) 'permission_handler_web_stub.dart';

// ✅ Device info is needed for Android version-specific logic
import 'package:device_info_plus/device_info_plus.dart';

/// Requests all Bluetooth and location permissions required by the app.
/// Returns [true] if the core requirements for connectivity are met.
Future<bool> requestPermissions() async {
  // 1. Web & Desktop: No runtime permissions needed for these targets
  if (kIsWeb || AppPlatform.isDesktop) return true;

  final List<Permission> toRequest = [];
  int sdkInt = 0;

  if (AppPlatform.isAndroid) {
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    sdkInt = androidInfo.version.sdkInt;
  }

  // ── 2. Connectivity (BT & Location) ──────────────────────────────────
  if (AppPlatform.isAndroid) {
    // network_info_plus needs location on ALL versions to read SSID
    toRequest.add(Permission.location);

    if (sdkInt >= 31) {
      // Android 12+ requires specific BT permissions
      toRequest.addAll([
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
      ]);
    }
  } else if (AppPlatform.isIOS) {
    toRequest.addAll([
      Permission.bluetooth,
      Permission.locationWhenInUse,
    ]);
  }

  // ── 3. Media & Hardware (Image Drop & Voice) ─────────────────────────
  toRequest.addAll([
    Permission.camera,
    Permission.microphone,
  ]);

  if (AppPlatform.isAndroid) {
    if (sdkInt >= 33) {
      // Android 13+ uses granular media + notification permissions
      toRequest.addAll([
        Permission.photos,
        Permission.videos,
        Permission.notification,
      ]);
    } else {
      // Android 12 and below use legacy storage
      toRequest.add(Permission.storage);
    }
  } else if (AppPlatform.isIOS) {
    toRequest.add(Permission.photos);
  }

  // ── 4. PERF: Filter out already granted permissions ──────────────────
  final List<Permission> actuallyNeeded = [];
  final statusesBefore = await Future.wait(toRequest.map((p) => p.status));

  for (int i = 0; i < toRequest.length; i++) {
    if (!statusesBefore[i].isGranted && !statusesBefore[i].isLimited) {
      actuallyNeeded.add(toRequest[i]);
    }
  }

  if (actuallyNeeded.isEmpty) return _validateCore(sdkInt);

  // ── 5. Batch Request ────────────────────────────────────────────────
  try {
    await actuallyNeeded.request();
  } catch (e) {
    debugPrint('[Permissions] Request Error: $e');
  }

  return _validateCore(sdkInt);
}

/// Helper to validate if the app has enough permission to actually function.
Future<bool> _validateCore(int sdkInt) async {
  if (AppPlatform.isAndroid) {
    final locStatus = await Permission.location.status;
    final bool hasLoc = locStatus.isGranted || locStatus.isLimited;

    if (sdkInt >= 31) {
      final scan = await Permission.bluetoothScan.status;
      final connect = await Permission.bluetoothConnect.status;
      return hasLoc &&
          (scan.isGranted || scan.isLimited) &&
          (connect.isGranted || connect.isLimited);
    }
    return hasLoc;
  }

  if (AppPlatform.isIOS) {
    final bt = await Permission.bluetooth.status;
    return bt.isGranted || bt.isLimited;
  }

  return true;
}
