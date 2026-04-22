import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'app_platform.dart';

class PermissionHelper {
  PermissionHelper._();

  /// Request all Bluetooth + Location permissions required on the current platform.
  /// Returns true if all necessary permissions are granted.
  static Future<bool> requestBluetoothPermissions() async {
    // Web and desktop: no runtime permissions needed via permission_handler
    if (!AppPlatform.needsRuntimePermissions) return true;

    final List<Permission> required = [];

    if (AppPlatform.isAndroid) {
      // Android 12+ (API 31+) uses new granular BT permissions.
      // permission_handler resolves the API level internally, so on API < 31,
      // requesting bluetoothScan will automatically ask for location instead.
      required.addAll([
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
        Permission.location,
      ]);
    } else if (AppPlatform.isIOS) {
      // iOS only needs bluetooth; location is NOT required for BLE on iOS 13+.
      required.add(Permission.bluetooth);
    }

    if (required.isEmpty) return true;

    final statuses = await required.request();

    // Debug logging for denied permissions
    for (final entry in statuses.entries) {
      if (!entry.value.isGranted && !entry.value.isLimited) {
        debugPrint(
            '[Permissions] Denied/Restricted: ${entry.key} → ${entry.value}');
      }
    }

    // ── Platform-specific evaluation ────────────────────────────────────────

    if (AppPlatform.isAndroid) {
      // Helper to check if a permission is functional (granted or limited)
      bool isGood(Permission p) {
        final status = statuses[p];
        return status != null && (status.isGranted || status.isLimited);
      }

      // We ensure scan, connect, and advertise are all functional.
      // (We don't strictly enforce Location here, because on Android 12+
      // location is often not needed if 'neverForLocation' is in the manifest).
      return isGood(Permission.bluetoothScan) &&
          isGood(Permission.bluetoothConnect) &&
          isGood(Permission.bluetoothAdvertise);
    } else if (AppPlatform.isIOS) {
      final status = statuses[Permission.bluetooth];
      return status != null && (status.isGranted || status.isLimited);
    }

    return true;
  }

  /// Opens the app settings page so the user can grant denied permissions.
  static Future<void> openSettings() => openAppSettings();
}
