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
  /// Returns [true] if the core requirements for connectivity are met.
  static Future<bool> requestAllPermissions() async {
    if (!AppPlatform.needsRuntimePermissions) return true;

    final List<Permission> permissionsToRequest = [];
    final int sdkInt = await _getAndroidSdk();

    // ── 1. Connectivity (Bluetooth & Location) ───────────────────────────
    if (AppPlatform.isAndroid) {
      // network_info_plus requires Location to see SSID on all versions
      permissionsToRequest.add(Permission.location);

      if (sdkInt >= 31) {
        // Android 12+ specific BT permissions
        permissionsToRequest.addAll([
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.bluetoothAdvertise,
        ]);
      }
      
      if (sdkInt >= 33) {
        // Android 13+ requires notifications for foreground services
        permissionsToRequest.add(Permission.notification);
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
        // Android 13+ Granular Media
        permissionsToRequest.addAll([
          Permission.photos,
          Permission.videos,
        ]);
      } else {
        // Legacy Android Storage
        permissionsToRequest.add(Permission.storage);
      }
    } else if (AppPlatform.isIOS) {
      permissionsToRequest.add(Permission.photos);
    }

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

    if (actuallyNeeded.isEmpty) return _validateCorePermissions();

    try {
      // Trigger the OS dialogs for the batch
      await actuallyNeeded.request();
    } catch (e) {
      debugPrint('[Permissions] Request Batch Error: $e');
    }

    return _validateCorePermissions();
  }

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
  }
}
