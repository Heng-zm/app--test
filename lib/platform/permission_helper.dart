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

  /// Requests all necessary permissions. Returns true if we can proceed.
  static Future<bool> requestAllPermissions() async {
    // 🟢 FIX: Immediate bypass for Desktop and Web.
    // These platforms handle permissions at the OS level/Entitlements, not runtime popups.
    if (kIsWeb || !AppPlatform.isMobile) return true;

    if (!AppPlatform.needsRuntimePermissions) return true;

    final int sdkInt = await _getAndroidSdk();
    final List<Permission> toRequest = [];

    // ── 1. Connectivity (Bluetooth & Location) ───────────────────────────
    if (AppPlatform.isAndroid) {
      toRequest.add(Permission.location);

      if (sdkInt >= 31) {
        toRequest.addAll([
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.bluetoothAdvertise,
        ]);
      }

      if (sdkInt >= 33) {
        toRequest.add(Permission.notification);
      }
    } else if (AppPlatform.isIOS) {
      toRequest.addAll([
        Permission.bluetooth,
        Permission.locationWhenInUse,
      ]);
    }

    // ── 2. Hardware & Media ──────────────────────────────────────────────
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

    // ── 3. Parallel Status Check ────────────────────────────────────────────
    final statuses = await Future.wait(toRequest.map((p) => p.status));

    final List<Permission> actuallyNeeded = [];
    for (int i = 0; i < toRequest.length; i++) {
      if (!statuses[i].isGranted && !statuses[i].isLimited) {
        actuallyNeeded.add(toRequest[i]);
      }
    }

    if (actuallyNeeded.isEmpty) return _validateCorePermissions(sdkInt);

    // ── 4. Request & Inspect Results ─────────────────────────────────────
    try {
      await actuallyNeeded.request();
    } catch (e) {
      debugPrint('[Permissions] Request batch error: $e');
    }

    return _validateCorePermissions(sdkInt);
  }

  /// Checks whether hardware services (BT/GPS) are enabled at the OS level.
  static Future<bool> areCoreServicesEnabled() async {
    if (kIsWeb || !AppPlatform.isMobile) return true;

    try {
      if (AppPlatform.isAndroid) {
        final results = await Future.wait([
          Permission.bluetooth.serviceStatus,
          Permission.location.serviceStatus,
        ]);
        return results.every((s) => s.isEnabled);
      }

      if (AppPlatform.isIOS) {
        // iOS: Bluetooth is handled via the CoreBluetooth manager (not this package),
        // so we check Location service status only.
        final status = await Permission.location.serviceStatus;
        return status.isEnabled;
      }
    } catch (e) {
      debugPrint('[Permissions] Service status check failed: $e');
      return true;
    }
    return true;
  }

  /// Returns true if photo/gallery access is granted.
  static Future<bool> hasPhotoPermission() async {
    if (kIsWeb || !AppPlatform.isMobile) return true;

    if (AppPlatform.isAndroid) {
      final int sdkInt = await _getAndroidSdk();
      if (sdkInt >= 33) {
        final res = await Future.wait(
            [Permission.photos.status, Permission.videos.status]);
        return res.every((s) => s.isGranted || s.isLimited);
      }
      return await Permission.storage.isGranted;
    }

    final status = await Permission.photos.status;
    return status.isGranted || status.isLimited;
  }

  static Future<void> openSettings() => openAppSettings();

  // ─────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Validates that the minimum required permissions are granted.
  static Future<bool> _validateCorePermissions(int? sdkInt) async {
    // 🟢 FIX: Desktop/Web are always valid here.
    if (kIsWeb || !AppPlatform.isMobile) return true;

    if (AppPlatform.isAndroid) {
      final int sdk = sdkInt ?? await _getAndroidSdk();

      final List<Future<PermissionStatus>> checks = [
        Permission.location.status
      ];
      if (sdk >= 31) {
        checks.addAll([
          Permission.bluetoothScan.status,
          Permission.bluetoothConnect.status,
        ]);
      }

      final statuses = await Future.wait(checks);
      return statuses.every((s) => s.isGranted || s.isLimited);
    }

    if (AppPlatform.isIOS) {
      final statuses = await Future.wait([
        Permission.bluetooth.status,
        Permission.locationWhenInUse.status,
      ]);
      return statuses.every((s) => s.isGranted || s.isLimited);
    }

    return true;
  }

  static Future<int> _getAndroidSdk() async {
    if (!AppPlatform.isAndroid) return 0;
    if (_cachedAndroidSdk != null) return _cachedAndroidSdk!;

    try {
      final info = await _deviceInfo.androidInfo;
      return _cachedAndroidSdk = info.version.sdkInt;
    } catch (e) {
      debugPrint('[Permissions] Failed to read SDK version: $e');
      return 0;
    }
  }
}
