import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'app_platform.dart';

class PermissionHelper {
  PermissionHelper._();

  /// Requests all necessary permissions (BT, Location, Camera, Photos, Mic).
  /// Returns true only if the "hard" requirements (Bluetooth/Location) are met.
  static Future<bool> requestAllPermissions() async {
    // Web and desktop: no runtime permissions needed via permission_handler
    if (!AppPlatform.needsRuntimePermissions) return true;

    final List<Permission> required = [];

    // ── Bluetooth & Location ────────────────────────────────────────────────
    if (AppPlatform.isAndroid) {
      required.addAll([
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
        Permission.location,
      ]);
    } else if (AppPlatform.isIOS) {
      required.add(Permission.bluetooth);
      required.add(Permission.locationWhenInUse);
    }

    // ── Media & Hardware ────────────────────────────────────────────────────
    required.addAll([
      Permission.camera,
      Permission.microphone,
      Permission
          .photos, // On Android 13+, this handles granular media permissions
    ]);

    if (required.isEmpty) return true;

    // Request everything in a single system batch
    final statuses = await required.request();

    // Debug logging for denied permissions
    for (final entry in statuses.entries) {
      if (!entry.value.isGranted && !entry.value.isLimited) {
        debugPrint('[Permissions] Denied: ${entry.key} → ${entry.value}');
      }
    }

    // ── Platform-Specific Validation ────────────────────────────────────────

    bool isGood(Permission p) {
      final status = statuses[p];
      // isLimited is successful (used for iOS "Selected Photos" mode)
      return status != null && (status.isGranted || status.isLimited);
    }

    if (AppPlatform.isAndroid) {
      // Android Core Requirements: Bluetooth (for connection)
      return isGood(Permission.bluetoothScan) &&
          isGood(Permission.bluetoothConnect) &&
          isGood(Permission.bluetoothAdvertise);
    } else if (AppPlatform.isIOS) {
      // iOS Core Requirements: Bluetooth
      return isGood(Permission.bluetooth);
    }

    return true;
  }

  /// Optional: Specifically request background location if needed for iOS
  static Future<bool> requestBackgroundLocation() async {
    if (AppPlatform.isIOS) {
      final status = await Permission.locationAlways.request();
      return status.isGranted;
    }
    return true;
  }

  /// Opens the app settings page
  static Future<void> openSettings() => openAppSettings();
}
