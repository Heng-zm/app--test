import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'app_platform.dart';

// ✅ Conditional import: Uses real package on mobile, and your stub on web.
import 'package:permission_handler/permission_handler.dart'
    if (dart.library.html) 'permission_handler_web_stub.dart';

class PermissionHelper {
  PermissionHelper._();

  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /// Requests all necessary permissions for the app in a single batch.
  static Future<bool> requestAllPermissions() async {
    if (!AppPlatform.needsRuntimePermissions) return true;

    final List<Permission> permissionsToRequest = [];

    // 🛠️ PERF: Cache SDK version once per request cycle
    int sdkInt = 0;
    if (AppPlatform.isAndroid) {
      final androidInfo = await _deviceInfo.androidInfo;
      sdkInt = androidInfo.version.sdkInt;
    }

    // ── 1. Connectivity (Bluetooth & Location) ───────────────────────────
    if (AppPlatform.isAndroid) {
      // network_info_plus (v7/v8) requires Location to see SSID on all versions
      permissionsToRequest.add(Permission.location);

      if (sdkInt >= 31) {
        // Android 12+ specific BT permissions
        permissionsToRequest.addAll([
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.bluetoothAdvertise,
        ]);
      }
    } else if (AppPlatform.isIOS) {
      permissionsToRequest.addAll([
        Permission.bluetooth,
        Permission.locationWhenInUse,
      ]);
    }

    // ── 2. Hardware & Media (Camera, Mic, Photos) ────────────────────────
    permissionsToRequest.addAll([
      Permission.camera,
      Permission.microphone,
    ]);

    if (AppPlatform.isAndroid) {
      if (sdkInt >= 33) {
        permissionsToRequest.addAll([
          Permission.photos,
          Permission.videos,
          Permission.notification,
        ]);
      } else {
        permissionsToRequest.add(Permission.storage);
      }
    } else if (AppPlatform.isIOS) {
      permissionsToRequest.add(Permission.photos);
    }

    // ── 3. Performance Check: Filter out already granted permissions ──────
    final statuses =
        await Future.wait(permissionsToRequest.map((p) => p.status));
    final List<Permission> actuallyNeeded = [];

    for (int i = 0; i < permissionsToRequest.length; i++) {
      final status = statuses[i];
      // Note: We treat 'limited' (iOS) as granted.
      if (!status.isGranted && !status.isLimited) {
        actuallyNeeded.add(permissionsToRequest[i]);
      }
    }

    if (actuallyNeeded.isEmpty) return _validateCorePermissions();

    try {
      await actuallyNeeded.request();
    } catch (e) {
      debugPrint('[Permissions] Request Batch Error: $e');
    }

    return _validateCorePermissions();
  }

  /// Validates core connectivity requirements based on OS version.
  static Future<bool> _validateCorePermissions() async {
    if (!AppPlatform.needsRuntimePermissions) return true;

    if (AppPlatform.isAndroid) {
      final androidInfo = await _deviceInfo.androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      final loc = await Permission.location.status;
      final bool hasLoc = loc.isGranted || loc.isLimited;

      if (sdkInt >= 31) {
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

  /// 🛠️ NEW: Checks if hardware services (Bluetooth/GPS) are physically turned ON.
  /// Useful for showing a "Please turn on Bluetooth" banner.
  static Future<bool> areCoreServicesEnabled() async {
    if (kIsWeb || !AppPlatform.isMobile) return true;

    // Check Bluetooth radio status
    final btService = await Permission.bluetooth.serviceStatus;
    // Check Location radio status (Required for discovery)
    final locService = await Permission.location.serviceStatus;

    return btService.isEnabled && locService.isEnabled;
  }

  /// Sequentially requests background location (OS requirement).
  static Future<bool> requestBackgroundLocation() async {
    if (!AppPlatform.isMobile) return true;

    var foreground = await Permission.location.status;
    if (!foreground.isGranted) {
      foreground = await Permission.location.request();
    }

    if (foreground.isGranted) {
      final background = await Permission.locationAlways.request();
      return background.isGranted;
    }
    return false;
  }

  /// Specifically check for Photo library access (Image Drop feature).
  static Future<bool> hasPhotoPermission() async {
    if (!AppPlatform.isMobile) return true;

    if (AppPlatform.isAndroid) {
      final info = await _deviceInfo.androidInfo;
      if (info.version.sdkInt >= 33) {
        final status = await Permission.photos.status;
        return status.isGranted || status.isLimited;
      }
      return await Permission.storage.isGranted;
    }

    final status = await Permission.photos.status;
    return status.isGranted || status.isLimited;
  }

  static Future<void> openSettings() async {
    await openAppSettings();
  }
}
