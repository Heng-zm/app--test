import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'app_platform.dart';

class PermissionHelper {
  PermissionHelper._();

  /// Requests all necessary permissions (BT, Location, Camera, Photos, Mic).
  /// Returns true only if the "hard" requirements (Bluetooth/Connection) are met.
  static Future<bool> requestAllPermissions() async {
    // Web and desktop: no runtime permissions needed via this handler
    if (!AppPlatform.needsRuntimePermissions) {
      return true;
    }

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
      // Permission.photos automatically maps to READ_MEDIA_IMAGES on Android 13+
      Permission.photos,
    ]);

    if (required.isEmpty) {
      return true;
    }

    // Request everything in a single system sequence
    final Map<Permission, PermissionStatus> statuses = await required.request();

    // Debug logging for denied/restricted permissions
    statuses.forEach((permission, status) {
      if (!status.isGranted && !status.isLimited) {
        debugPrint('[Permissions] Restricted: $permission -> $status');
      }
    });

    // ── Platform-Specific Validation Helper ─────────────────────────────────

    bool isGood(Permission p) {
      final status = statuses[p];
      // isLimited is treated as success (specifically for iOS Photo Library)
      return status != null && (status.isGranted || status.isLimited);
    }

    // ── Final Evaluation ────────────────────────────────────────────────────

    if (AppPlatform.isAndroid) {
      // Core requirements for Android 12+: Scan + Connect + Advertise
      // We do not strictly fail on 'location' here because Scan handles it.
      return isGood(Permission.bluetoothScan) &&
          isGood(Permission.bluetoothConnect) &&
          isGood(Permission.bluetoothAdvertise);
    }

    if (AppPlatform.isIOS) {
      // Core requirement for iOS: Bluetooth
      return isGood(Permission.bluetooth);
    }

    return true;
  }

  /// Specifically request background location if needed for persistent links.
  static Future<bool> requestBackgroundLocation() async {
    if (AppPlatform.isIOS) {
      final status = await Permission.locationAlways.request();
      return status.isGranted;
    }
    return true;
  }

  /// Opens the system settings page for the app so the user can manually
  /// enable any denied permissions.
  static Future<void> openSettings() async {
    await openAppSettings();
  }
}
