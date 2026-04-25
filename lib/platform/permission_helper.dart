import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'app_platform.dart';

// The conditional import resolves to the real package on mobile/desktop and
// falls back to the in-package web stub on dart:html (web) targets.
// IMPORTANT: The stub path must be a full package: URI so the Dart compiler
// can locate it regardless of which file triggers the build.
import 'package:permission_handler/permission_handler.dart'
    if (dart.library.html) 'package:bluetooth_chat/platform/permission_handler_web_stub.dart';

class PermissionHelper {
  PermissionHelper._();

  // PERF: Module-level singleton — DeviceInfoPlugin is stateless and safe to
  // reuse. Avoids re-instantiation on every static method call.
  // FIX: `const` → `final`: DeviceInfoPlugin() has no const constructor so it
  // cannot be assigned to a const field; final preserves the singleton intent.
  static final _deviceInfo = DeviceInfoPlugin();

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Requests all necessary permissions for the app in a single batch.
  ///
  /// Returns `true` if every core permission is satisfied after the request.
  static Future<bool> requestAllPermissions() async {
    if (!AppPlatform.needsRuntimePermissions) return true;

    // PERF: Fetch SDK once and thread it through — avoids a second async
    // device-info round-trip inside _validateCorePermissions.
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
    // PERF: Fetch all statuses in parallel — one round-trip instead of N
    // sequential awaits.
    final statuses =
        await Future.wait(permissionsToRequest.map((p) => p.status));

    final List<Permission> actuallyNeeded = [
      for (int i = 0; i < permissionsToRequest.length; i++)
        if (!statuses[i].isGranted && !statuses[i].isLimited)
          permissionsToRequest[i],
    ];

    if (actuallyNeeded.isEmpty) return _validateCorePermissions(sdkInt);

    // ── 4. Request & Inspect Results ─────────────────────────────────────
    // FIX: Capture the result map and log permanently denied permissions so
    // callers know they must direct the user to app settings.
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
  /// at the OS level — distinct from whether *permissions* are granted.
  ///
  /// FIX: Split service checks by platform. Android and iOS expose different
  /// service statuses; checking Bluetooth service status on a platform that
  /// doesn't support it throws or returns a misleading result.
  static Future<bool> areCoreServicesEnabled() async {
    if (kIsWeb || !AppPlatform.isMobile) return true;

    if (AppPlatform.isAndroid) {
      // Android: both BT and Location services must be on.
      final results = await Future.wait([
        Permission.bluetooth.serviceStatus,
        Permission.location.serviceStatus,
      ]);
      return results.every((s) => s.isEnabled);
    }

    if (AppPlatform.isIOS) {
      // iOS: CoreBluetooth manages its own auth flow; Location is the
      // relevant runtime service check here.
      final locationService = await Permission.location.serviceStatus;
      return locationService.isEnabled;
    }

    return true;
  }

  /// Requests background location, first ensuring foreground is granted.
  ///
  /// FIX: Removed implicit fall-through logic. The previous code had a
  /// shadowed re-assignment of `foreground` that made the denied path
  /// ambiguous — now uses explicit early returns for clarity.
  static Future<bool> requestBackgroundLocation() async {
    if (!AppPlatform.isMobile) return true;

    final foregroundStatus = await Permission.location.status;

    // Only prompt if not already granted — avoids double-prompting.
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
        // PERF: Check photos and videos in parallel — both are required for
        // full media access on API 33+.
        final statuses = await Future.wait([
          Permission.photos.status,
          Permission.videos.status,
        ]);
        return statuses.every((s) => s.isGranted || s.isLimited);
      }
      // API < 33: broad storage permission covers both.
      return Permission.storage.isGranted;
    }

    // iOS
    final status = await Permission.photos.status;
    return status.isGranted || status.isLimited;
  }

  /// Opens the OS app-settings page so the user can manually grant
  /// permissions that were permanently denied.
  static Future<void> openSettings() => openAppSettings();

  // ─────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Validates that the minimum required permissions are granted.
  ///
  /// Accepts [sdkInt] to avoid a redundant _getAndroidSdk() call when invoked
  /// from [requestAllPermissions]. Pass `null` to fetch the SDK lazily (e.g.
  /// for standalone resume checks via [corePermissionsGranted]).
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
