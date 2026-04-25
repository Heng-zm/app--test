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
<<<<<<< HEAD
  ///
  /// Returns `true` if every core permission is satisfied after the request.
=======
  /// Returns [true] if the core requirements for connectivity are met.
>>>>>>> 522876f668e35371f5dd4a135ff5fb093232b4d9
  static Future<bool> requestAllPermissions() async {
    if (!AppPlatform.needsRuntimePermissions) return true;

    final int sdkInt = await _getAndroidSdk();
    final List<Permission> permissionsToRequest = [];
<<<<<<< HEAD

    // ── 1. Connectivity (Bluetooth & Location) ───────────────────────────
    if (AppPlatform.isAndroid) {
=======
    final int sdkInt = await _getAndroidSdk();

    // ── 1. Connectivity (Bluetooth & Location) ───────────────────────────
    if (AppPlatform.isAndroid) {
      // network_info_plus requires Location to see SSID on all versions
>>>>>>> 522876f668e35371f5dd4a135ff5fb093232b4d9
      permissionsToRequest.add(Permission.location);

      if (sdkInt >= 31) {
        permissionsToRequest.addAll([
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.bluetoothAdvertise,
        ]);
      }
<<<<<<< HEAD

      if (sdkInt >= 33) {
=======
      
      if (sdkInt >= 33) {
        // Android 13+ requires notifications for foreground services
>>>>>>> 522876f668e35371f5dd4a135ff5fb093232b4d9
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
<<<<<<< HEAD
        permissionsToRequest.addAll([Permission.photos, Permission.videos]);
=======
        // Android 13+ Granular Media
        permissionsToRequest.addAll([
          Permission.photos,
          Permission.videos,
        ]);
>>>>>>> 522876f668e35371f5dd4a135ff5fb093232b4d9
      } else {
        // Legacy Android Storage
        permissionsToRequest.add(Permission.storage);
      }
    } else if (AppPlatform.isIOS) {
      permissionsToRequest.add(Permission.photos);
    }

<<<<<<< HEAD
    // ── 3. Batch Status Check ────────────────────────────────────────────
    final statuses =
        await Future.wait(permissionsToRequest.map((p) => p.status));

    final List<Permission> actuallyNeeded = [
      for (int i = 0; i < permissionsToRequest.length; i++)
        if (!statuses[i].isGranted && !statuses[i].isLimited)
          permissionsToRequest[i],
    ];
=======
    // ── 3. Performance Check: Filter out already granted permissions ──────
    // 🛠️ PERF: Parallelize status checks to avoid blocking the main thread
    final statuses = await Future.wait(permissionsToRequest.map((p) => p.status));
    final List<Permission> actuallyNeeded = [];

    for (int i = 0; i < permissionsToRequest.length; i++) {
      final status = statuses[i];
      // We treat 'granted' and 'limited' (common on iOS photo picker) as success
      if (!status.isGranted && !status.isLimited) {
        actuallyNeeded.add(permissionsToRequest[i]);
      }
    }
>>>>>>> 522876f668e35371f5dd4a135ff5fb093232b4d9

    if (actuallyNeeded.isEmpty) return _validateCorePermissions(sdkInt);

    // ── 4. Request & Inspect Results ─────────────────────────────────────
    try {
<<<<<<< HEAD
      final results = await actuallyNeeded.request();
      final denied = results.entries
          .where((e) => e.value.isPermanentlyDenied)
          .map((e) => e.key.toString())
          .toList();
      if (denied.isNotEmpty) {
        debugPrint('[Permissions] Permanently denied: $denied '
            '— user must grant via app settings.');
      }
=======
      // Trigger the OS dialogs for the batch
      await actuallyNeeded.request();
>>>>>>> 522876f668e35371f5dd4a135ff5fb093232b4d9
    } catch (e) {
      debugPrint('[Permissions] Request batch error: $e');
    }

    return _validateCorePermissions(sdkInt);
  }

<<<<<<< HEAD
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
=======
  /// 🛠️ FIX: Validates if the app has the MINIMUM permissions required to work.
  static Future<bool> _validateCorePermissions() async {
    if (!AppPlatform.needsRuntimePermissions) return true;

    if (AppPlatform.isAndroid) {
      final int sdkInt = await _getAndroidSdk();
      
      // Location is essential for discovery/SSID
      final locStatus = await Permission.location.status;
      final bool hasLoc = locStatus.isGranted || locStatus.isLimited;

      if (sdkInt >= 31) {
        // Android 12+ needs Scan AND Connect
>>>>>>> 522876f668e35371f5dd4a135ff5fb093232b4d9
        final btStatuses = await Future.wait([
          Permission.bluetoothScan.status,
          Permission.bluetoothConnect.status,
        ]);
        return hasLoc && btStatuses.every((s) => s.isGranted || s.isLimited);
      }
      return hasLoc;
    }

    if (AppPlatform.isIOS) {
      // iOS uses the unified Bluetooth constant
      final statuses = await Future.wait([
        Permission.bluetooth.status,
        Permission.locationWhenInUse.status,
      ]);
      return statuses.every((s) => s.isGranted || s.isLimited);
    }

    return true;
  }

<<<<<<< HEAD
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
=======
  /// Checks if hardware radios (Bluetooth/GPS) are physically toggled ON.
  static Future<bool> areCoreServicesEnabled() async {
    if (kIsWeb || !AppPlatform.isMobile) return true;

    // Check if the hardware switches are on
    final results = await Future.wait([
      Permission.bluetooth.serviceStatus,
      Permission.location.serviceStatus,
    ]);

    return results.every((s) => s.isEnabled);
  }

  /// Logic for Background Location (Requires sequential flow)
  static Future<bool> requestBackgroundLocation() async {
    if (!AppPlatform.isMobile) return true;

    // 1. Check/Request Foreground first (OS Requirement)
    var foreground = await Permission.location.status;
    if (!foreground.isGranted) {
      foreground = await Permission.location.request();
    }

    // 2. Only then request "Always"
    if (foreground.isGranted) {
      final background = await Permission.locationAlways.request();
      return background.isGranted;
    }
    return false;
  }

  /// Specific check for the Image/Video drop feature
  static Future<bool> hasPhotoPermission() async {
    if (!AppPlatform.isMobile) return true;

    if (AppPlatform.isAndroid) {
      final int sdkInt = await _getAndroidSdk();
      if (sdkInt >= 33) {
        final status = await Permission.photos.status;
        return status.isGranted || status.isLimited;
      }
      return await Permission.storage.isGranted;
    }

    final status = await Permission.photos.status;
    return status.isGranted || status.isLimited;
  }

  /// Internal helper to minimize redundant device info calls
  static Future<int> _getAndroidSdk() async {
    if (!AppPlatform.isAndroid) return 0;
    try {
      final info = await _deviceInfo.androidInfo;
      return info.version.sdkInt;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> openSettings() async {
    await openAppSettings();
>>>>>>> 522876f668e35371f5dd4a135ff5fb093232b4d9
  }
}
