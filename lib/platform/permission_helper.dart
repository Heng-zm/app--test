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
      // permission_handler resolves the API level internally.
      required.addAll([
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
        Permission.location, // still needed for Classic BT discovery on API < 31
      ]);
    } else if (AppPlatform.isIOS) {
      // iOS only needs bluetooth; location is NOT required for BLE on iOS 13+.
      required.add(Permission.bluetooth);
    }

    if (required.isEmpty) return true;

    final statuses = await required.request();

    // Check that every requested permission is granted or limited
    for (final entry in statuses.entries) {
      if (!entry.value.isGranted && !entry.value.isLimited) {
        debugPrint('[Permissions] Denied: ${entry.key} → ${entry.value}');
        // Non-fatal — continue; the service will surface its own error
      }
    }

    // Bluetooth connect + scan are the hard requirements
    final btConnect = statuses[Permission.bluetoothConnect];
    final btScan = statuses[Permission.bluetoothScan];
    final bt = statuses[Permission.bluetooth];

    if (AppPlatform.isAndroid) {
      return (btConnect?.isGranted ?? false) && (btScan?.isGranted ?? false);
    } else if (AppPlatform.isIOS) {
      return bt?.isGranted ?? false;
    }
    return true;
  }

  /// Opens the app settings page so the user can grant denied permissions.
  static Future<void> openSettings() => openAppSettings();
}
