import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'app_platform.dart';

import 'package:permission_handler/permission_handler.dart'
    if (dart.library.html) 'package:bluetooth_chat/platform/permission_handler_web_stub.dart';

class PermissionHelper {
  PermissionHelper._();

  // PERF: Module-level singleton — DeviceInfoPlugin is stateless and safe to
  // reuse. Avoids re-instantiation on every static method call.
  // FIX: `const` → `final`: DeviceInfoPlugin() has no const constructor.
  static final _deviceInfo = DeviceInfoPlugin();

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Requests all necessary permissions for the app in a single batch.
  ///
  /// Returns `true` if every core permission is satisfied after the request.
  static Future<bool> requestAllPermissions() async {
    if (!AppPlatform.needsRuntimePermissions) return true;

    final int sdkInt = await _getAndroidSdk();
    final List<Permission> permissionsToRequest = [];

    // ── 1. Connectivity (Bluetooth & Location) ───────────────────────────
    if (AppPlatform.isAndroid) {
      permissionsToRequest.add(Permission.location);

      if (sdkInt >= 31) {
        permissionsToRequest.addAll([
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.bluetoothAdvertise,
        ]);
      }

      if (sdkInt >= 33) {
        permissionsToRequest.add(Permission.notification);
      }
    } else if (AppPlatform.isIOS) {
      permissionsToRequest.addAll([
        Permission.bluetooth,
        Permission.locationWhenInUse,
      ]);
    }

    // ── 2. Hardware & Media ──────────────────────────────────────────────
    permissionsToRequest.addAll([
      Permission.camera,
      Permission.microphone,
    ]);

    if (AppPlatform.isAndroid) {
      if (sdkInt >= 33) {
        permissionsToRequest.addAll([Permission.photos, Permission.videos]);
      } else {
        permissionsToRequest.add(Permission.storage);
      }
    } else if (AppPlatform.isIOS) {
      permissionsToRequest.add(Permission.photos);
    }

    // ── 3. Batch Status Check ────────────────────────────────────────────
    final statuses =
        await Future.wait(permissionsToRequest.map((p) => p.status));

    final List<Permission> actuallyNeeded = [
      for (int i = 0; i < permissionsToRequest.length; i++)
        if (!statuses[i].isGranted && !statuses[i].isLimited)
          permissionsToRequest[i],
    ];

    if (actuallyNeeded.isEmpty) return _validateCorePermissions(sdkInt);

    // ── 4. Request & Inspect Results ─────────────────────────────────────
    try {
      final results = await actuallyNeeded.request();
      final denied = results.entries
          .where((e) => e.value.isPermanentlyDenied)
          .map((e) => e.key.toString())
          .toList();
      if (denied.isNotEmpty) {
        debugPrint('[Permissions] Permanently denied: $denied '
            '— user must grant via app settings.');
      }
    } catch (e) {
      debugPrint('[Permissions] Request batch error: $e');
    }

    return _validateCorePermissions(sdkInt);
  }

  /// Returns `true` if all core permissions are currently satisfied without
  /// triggering any prompts. Useful for resume / foreground checks.
  static Future<bool> corePermissionsGranted() =>
      _validateCorePermissions(null);

  /// Checks whether core hardware services (Bluetooth, Location) are enabled
  /// at the OS level — distinct from whether permissions are granted.
  static Future<bool> areCoreServicesEnabled() async {
    if (kIsWeb || !AppPlatform.isMobile) return true;

    if (AppPlatform.isAndroid) {
      final results = await Future.wait([
        Permission.bluetooth.serviceStatus,
        Permission.location.serviceStatus,
      ]);
      return results.every((s) => s.isEnabled);
    }

    if (AppPlatform.isIOS) {
      final locationService = await Permission.location.serviceStatus;
      return locationService.isEnabled;
    }

    return true;
  }

  /// Requests background location, first ensuring foreground is granted.
  static Future<bool> requestBackgroundLocation() async {
    if (!AppPlatform.isMobile) return true;

    final foregroundStatus = await Permission.location.status;

    final bool hasForeground = foregroundStatus.isGranted
        ? true
        : (await Permission.location.request()).isGranted;

    if (!hasForeground) {
      debugPrint('[Permissions] Foreground location denied; '
          'cannot request background.');
      return false;
    }

    final background = await Permission.locationAlways.request();
    return background.isGranted;
  }

  /// Returns `true` if the user has sufficient photo / storage access.
  static Future<bool> hasPhotoPermission() async {
    if (!AppPlatform.isMobile) return true;

    if (AppPlatform.isAndroid) {
      final int sdkInt = await _getAndroidSdk();
      if (sdkInt >= 33) {
        final statuses = await Future.wait([
          Permission.photos.status,
          Permission.videos.status,
        ]);
        return statuses.every((s) => s.isGranted || s.isLimited);
      }
      return Permission.storage.isGranted;
    }

    final status = await Permission.photos.status;
    return status.isGranted || status.isLimited;
  }

  /// Opens the OS app-settings page so the user can manually grant
  /// permissions that were permanently denied.
  static Future<void> openSettings() => openAppSettings();

  // ─────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────────────────────────────────────

  static Future<bool> _validateCorePermissions(int? sdkInt) async {
    if (!AppPlatform.needsRuntimePermissions) return true;

    if (AppPlatform.isAndroid) {
      final int sdk = sdkInt ?? await _getAndroidSdk();
      final locStatus = await Permission.location.status;
      final bool hasLoc = locStatus.isGranted || locStatus.isLimited;

      if (sdk >= 31) {
        final btStatuses = await Future.wait([
          Permission.bluetoothScan.status,
          Permission.bluetoothConnect.status,
        ]);
        return hasLoc && btStatuses.every((s) => s.isGranted || s.isLimited);
      }
      return hasLoc;
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

  /// Returns the Android SDK integer, or `0` on non-Android or error.
  static Future<int> _getAndroidSdk() async {
    if (!AppPlatform.isAndroid) return 0;
    try {
      final info = await _deviceInfo.androidInfo;
      return info.version.sdkInt;
    } catch (e) {
      debugPrint('[Permissions] Failed to read Android SDK version: $e');
      return 0;
    }
  }
}
