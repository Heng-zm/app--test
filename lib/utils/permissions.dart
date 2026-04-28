import 'package:flutter/foundation.dart';
import '../platform/app_platform.dart';

// ✅ Conditional import to prevent web compilation errors
import 'package:permission_handler/permission_handler.dart'
    if (dart.library.html) 'permission_handler_web_stub.dart';

import 'package:device_info_plus/device_info_plus.dart';

/// Cache the SDK version to avoid repeated native bridge calls
int? _cachedSdkInt;

/// Requests all Bluetooth and location permissions required by the app.
/// Returns [true] if the core requirements for connectivity are met.
Future<bool> requestPermissions() async {
  // 1. Web & Desktop: No runtime permissions needed for these targets
  if (kIsWeb || !AppPlatform.isMobile) return true;

  final List<Permission> toRequest = [];

  // 🟢 PERF: Fetch or use cached Android SDK version
  int sdkInt = 0;
  if (AppPlatform.isAndroid) {
    if (_cachedSdkInt != null) {
      sdkInt = _cachedSdkInt!;
    } else {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      sdkInt = _cachedSdkInt = androidInfo.version.sdkInt;
    }
  }

  // ── 2. Connectivity (BT & Location) ──────────────────────────────────
  if (AppPlatform.isAndroid) {
    // Required for both Bluetooth discovery and WiFi SSID reading
    toRequest.add(Permission.location);

    if (sdkInt >= 31) {
      toRequest.addAll([
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
      ]);
    }

    if (sdkInt >= 33) {
      toRequest.add(Permission.notification); // Required for scanning stability
    }
  } else if (AppPlatform.isIOS) {
    toRequest.addAll([
      Permission.bluetooth,
      Permission.locationWhenInUse,
    ]);
  }

  // ── 3. Media & Hardware ──────────────────────────────────────────────
  toRequest.addAll([
    Permission.camera,
    Permission.microphone,
  ]);

  if (AppPlatform.isAndroid) {
    if (sdkInt >= 33) {
      toRequest.addAll([Permission.photos, Permission.videos]);
    } else {
      toRequest.add(Permission.storage);
    }
  } else if (AppPlatform.isIOS) {
    toRequest.add(Permission.photos);
  }

  // ── 4. PERF: Check current statuses in parallel before requesting ────
  final statuses = await Future.wait(toRequest.map((p) => p.status));
  final List<Permission> actuallyNeeded = [];

  for (int i = 0; i < toRequest.length; i++) {
    if (!statuses[i].isGranted && !statuses[i].isLimited) {
      actuallyNeeded.add(toRequest[i]);
    }
  }

  if (actuallyNeeded.isEmpty) return _validateCore(sdkInt);

  // ── 5. Batch Request ────────────────────────────────────────────────
  try {
    // Batch request is handled natively by the OS for better UX
    await actuallyNeeded.request();
  } catch (e) {
    debugPrint('[Permissions] Batch Request Error: $e');
  }

  return _validateCore(sdkInt);
}

/// Helper to validate if the app has enough permission to actually function.
Future<bool> _validateCore(int sdkInt) async {
  if (AppPlatform.isAndroid) {
    // 🟢 PERF: Check all core statuses in parallel
    final List<Future<PermissionStatus>> coreChecks = [
      Permission.location.status
    ];

    if (sdkInt >= 31) {
      coreChecks.add(Permission.bluetoothScan.status);
      coreChecks.add(Permission.bluetoothConnect.status);
    }

    final coreStatuses = await Future.wait(coreChecks);
    return coreStatuses.every((s) => s.isGranted || s.isLimited);
  }

  if (AppPlatform.isIOS) {
    final btStatus = await Permission.bluetooth.status;
    return btStatus.isGranted || btStatus.isLimited;
  }

  return true;
}
