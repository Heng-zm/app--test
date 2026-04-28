import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'app_platform.dart';

// The conditional import resolves to the real package on mobile/desktop and
// falls back to the in-package web stub on dart:html (web) targets.
import 'package:permission_handler/permission_handler.dart'
    if (dart.library.html) 'package:bluetooth_chat/platform/permission_handler_web_stub.dart';

class PermissionHelper {
  PermissionHelper._();

  static final _deviceInfo = DeviceInfoPlugin();
  static int? _cachedAndroidSdk;

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Requests all necessary permissions in a single batch.
  /// Returns [true] if the app has sufficient rights to operate.
  static Future<bool> requestAllPermissions() async {
    // 🟢 PERF: Immediate bypass for non-mobile platforms.
    if (kIsWeb || !AppPlatform.isMobile) return true;

    final int sdkInt = await _getAndroidSdk();
    final List<Permission> toRequest = [];

    // ── 1. Connectivity ──────────────────────────────────────────────────
    if (AppPlatform.isAndroid) {
      toRequest.add(Permission.location);
      if (sdkInt >= 31) {
        toRequest.addAll([
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.bluetoothAdvertise,
        ]);
      }
      if (sdkInt >= 33) toRequest.add(Permission.notification);
    } else if (AppPlatform.isIOS) {
      toRequest.addAll([Permission.bluetooth, Permission.locationWhenInUse]);
    }

    // ── 2. Media ─────────────────────────────────────────────────────────
    toRequest.addAll([Permission.camera, Permission.microphone]);
    if (AppPlatform.isAndroid) {
      if (sdkInt >= 33) {
        toRequest.addAll([Permission.photos, Permission.videos]);
      } else {
        toRequest.add(Permission.storage);
      }
    } else if (AppPlatform.isIOS) {
      toRequest.add(Permission.photos);
    }

    // ── 3. Parallel Status Check ─────────────────────────────────────────
    final statuses = await Future.wait(toRequest.map((p) => p.status));
    final List<Permission> actuallyNeeded = [];

    for (int i = 0; i < toRequest.length; i++) {
      if (!statuses[i].isGranted && !statuses[i].isLimited) {
        actuallyNeeded.add(toRequest[i]);
      }
    }

    if (actuallyNeeded.isEmpty) return _validateCorePermissions(sdkInt);

    // ── 4. Batch Request ─────────────────────────────────────────────────
    try {
      await actuallyNeeded.request();
    } catch (e) {
      debugPrint('[Permissions] Request error: $e');
    }

    return _validateCorePermissions(sdkInt);
  }

  /// Non-blocking check for core permissions. 
  /// Useful for UI updates without triggering system dialogs.
  static Future<bool> corePermissionsGranted() async => 
      _validateCorePermissions(await _getAndroidSdk());

  /// Checks if hardware radios (BT/GPS) are enabled at the system level.
  static Future<bool> areCoreServicesEnabled() async {
    if (kIsWeb || !AppPlatform.isMobile) return true;

    try {
      if (AppPlatform.isAndroid) {
        // 🟢 PERF: Concurrent hardware status check
        final results = await Future.wait([
          Permission.bluetooth.serviceStatus,
          Permission.location.serviceStatus,
        ]);
        return results.every((s) => s.isEnabled);
      }

      if (AppPlatform.isIOS) {
        // iOS: Bluetooth status is handled by CoreBluetooth; we check Location here.
        return (await Permission.location.serviceStatus).isEnabled;
      }
    } catch (_) {
      return true; // Default to true to prevent blocking UI on OS errors
    }
    return true;
  }

  /// Returns [true] if the app can access the photo gallery.
  static Future<bool> hasPhotoPermission() async {
    if (kIsWeb || !AppPlatform.isMobile) return true;

    if (AppPlatform.isAndroid) {
      final sdk = await _getAndroidSdk();
      if (sdk >= 33) {
        final res = await Future.wait([Permission.photos.status, Permission.videos.status]);
        return res.every((s) => s.isGranted || s.isLimited);
      }
      return await Permission.storage.isGranted;
    }

    final iosStatus = await Permission.photos.status;
    return iosStatus.isGranted || iosStatus.isLimited;
  }

  /// Opens the system app settings screen.
  static Future<void> openSettings() => openAppSettings();

  // ─────────────────────────────────────────────────────────────────────────
  // Internal Helpers
  // ─────────────────────────────────────────────────────────────────────────

  static Future<bool> _validateCorePermissions(int sdkInt) async {
    if (kIsWeb || !AppPlatform.isMobile) return true;

    if (AppPlatform.isAndroid) {
      final List<Future<PermissionStatus>> core = [Permission.location.status];
      if (sdkInt >= 31) {
        core.addAll([Permission.bluetoothScan.status, Permission.bluetoothConnect.status]);
      }
      final res = await Future.wait(core);
      return res.every((s) => s.isGranted || s.isLimited);
    }

    if (AppPlatform.isIOS) {
      final res = await Future.wait([Permission.bluetooth.status, Permission.locationWhenInUse.status]);
      return res.every((s) => s.isGranted || s.isLimited);
    }

    return true;
  }

  static Future<int> _getAndroidSdk() async {
    if (!AppPlatform.isAndroid) return 0;
    if (_cachedAndroidSdk != null) return _cachedAndroidSdk!;

    try {
      final info = await _deviceInfo.androidInfo;
      return _cachedAndroidSdk = info.version.sdkInt;
    } catch (_) {
      return 0;
    }
  }
}
