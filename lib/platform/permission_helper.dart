import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'app_platform.dart';

// The conditional import resolves to the real package on mobile/desktop and
// falls back to the in-package web stub on dart:html (web) targets.
<<<<<<< HEAD
=======
// IMPORTANT: The stub path must be a full package: URI so the Dart compiler
// can locate it regardless of which file triggers the build.
>>>>>>> a53763d320be7b320454131c4120cbc49f48e947
import 'package:permission_handler/permission_handler.dart'
    if (dart.library.html) 'package:bluetooth_chat/platform/permission_handler_web_stub.dart';

class PermissionHelper {
  PermissionHelper._();

<<<<<<< HEAD
=======
  // PERF: Module-level singleton — DeviceInfoPlugin is stateless and safe to
  // reuse. Avoids re-instantiation on every static method call.
  // FIX: `const` → `final`: DeviceInfoPlugin() has no const constructor so it
  // cannot be assigned to a const field; final preserves the singleton intent.
>>>>>>> a53763d320be7b320454131c4120cbc49f48e947
  static final _deviceInfo = DeviceInfoPlugin();
  static int? _cachedAndroidSdk;

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

<<<<<<< HEAD
  /// Requests all necessary permissions. Returns true if we can proceed.
=======
  /// Requests all necessary permissions for the app in a single batch.
  ///
  /// Returns `true` if every core permission is satisfied after the request.
>>>>>>> a53763d320be7b320454131c4120cbc49f48e947
  static Future<bool> requestAllPermissions() async {
    // 🟢 FIX: Immediate bypass for Desktop and Web.
    // These platforms handle permissions at the OS level/Entitlements, not runtime popups.
    if (kIsWeb || !AppPlatform.isMobile) return true;

    if (!AppPlatform.needsRuntimePermissions) return true;

    // PERF: Fetch SDK once and thread it through — avoids a second async
    // device-info round-trip inside _validateCorePermissions.
    final int sdkInt = await _getAndroidSdk();
<<<<<<< HEAD
    final List<Permission> toRequest = [];

    // ── 1. Connectivity (Bluetooth & Location) ───────────────────────────
    if (AppPlatform.isAndroid) {
      toRequest.add(Permission.location);
=======

    final List<Permission> permissionsToRequest = [];

    // ── 1. Connectivity (Bluetooth & Location) ───────────────────────────
    if (AppPlatform.isAndroid) {
      permissionsToRequest.add(Permission.location);
>>>>>>> a53763d320be7b320454131c4120cbc49f48e947

      if (sdkInt >= 31) {
        toRequest.addAll([
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.bluetoothAdvertise,
        ]);
      }

      if (sdkInt >= 33) {
<<<<<<< HEAD
        toRequest.add(Permission.notification);
=======
        permissionsToRequest.add(Permission.notification);
>>>>>>> a53763d320be7b320454131c4120cbc49f48e947
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
<<<<<<< HEAD
        toRequest.addAll([Permission.photos, Permission.videos]);
      } else {
        toRequest.add(Permission.storage);
=======
        permissionsToRequest.addAll([Permission.photos, Permission.videos]);
      } else {
        permissionsToRequest.add(Permission.storage);
>>>>>>> a53763d320be7b320454131c4120cbc49f48e947
      }
    } else if (AppPlatform.isIOS) {
      toRequest.add(Permission.photos);
    }

<<<<<<< HEAD
    // ── 3. Parallel Status Check ────────────────────────────────────────────
    final statuses = await Future.wait(toRequest.map((p) => p.status));

    final List<Permission> actuallyNeeded = [];
    for (int i = 0; i < toRequest.length; i++) {
      if (!statuses[i].isGranted && !statuses[i].isLimited) {
        actuallyNeeded.add(toRequest[i]);
      }
    }
=======
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
>>>>>>> a53763d320be7b320454131c4120cbc49f48e947

    if (actuallyNeeded.isEmpty) return _validateCorePermissions(sdkInt);

    // ── 4. Request & Inspect Results ─────────────────────────────────────
    // FIX: Capture the result map and log permanently denied permissions so
    // callers know they must direct the user to app settings.
    try {
<<<<<<< HEAD
      await actuallyNeeded.request();
=======
      final results = await actuallyNeeded.request();
      final denied = results.entries
          .where((e) => e.value.isPermanentlyDenied)
          .map((e) => e.key.toString())
          .toList();
      if (denied.isNotEmpty) {
        debugPrint('[Permissions] Permanently denied: $denied '
            '— user must grant via app settings.');
      }
>>>>>>> a53763d320be7b320454131c4120cbc49f48e947
    } catch (e) {
      debugPrint('[Permissions] Request batch error: $e');
    }

    return _validateCorePermissions(sdkInt);
  }

<<<<<<< HEAD
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
=======
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
>>>>>>> a53763d320be7b320454131c4120cbc49f48e947
    }
    return true;
  }

<<<<<<< HEAD
  /// Returns true if photo/gallery access is granted.
=======
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
>>>>>>> a53763d320be7b320454131c4120cbc49f48e947
  static Future<bool> hasPhotoPermission() async {
    if (kIsWeb || !AppPlatform.isMobile) return true;

    if (AppPlatform.isAndroid) {
      final int sdkInt = await _getAndroidSdk();
      if (sdkInt >= 33) {
<<<<<<< HEAD
        final res = await Future.wait(
            [Permission.photos.status, Permission.videos.status]);
        return res.every((s) => s.isGranted || s.isLimited);
      }
      return await Permission.storage.isGranted;
=======
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
>>>>>>> a53763d320be7b320454131c4120cbc49f48e947
    }

    // iOS
    final status = await Permission.photos.status;
    return status.isGranted || status.isLimited;
  }

  static Future<void> openSettings() => openAppSettings();

  // ─────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Validates that the minimum required permissions are granted.
<<<<<<< HEAD
=======
  ///
  /// Accepts [sdkInt] to avoid a redundant _getAndroidSdk() call when invoked
  /// from [requestAllPermissions]. Pass `null` to fetch the SDK lazily (e.g.
  /// for standalone resume checks via [corePermissionsGranted]).
>>>>>>> a53763d320be7b320454131c4120cbc49f48e947
  static Future<bool> _validateCorePermissions(int? sdkInt) async {
    // 🟢 FIX: Desktop/Web are always valid here.
    if (kIsWeb || !AppPlatform.isMobile) return true;

    if (AppPlatform.isAndroid) {
      final int sdk = sdkInt ?? await _getAndroidSdk();

      final List<Future<PermissionStatus>> checks = [
        Permission.location.status
      ];
      if (sdk >= 31) {
<<<<<<< HEAD
        checks.addAll([
=======
        final btStatuses = await Future.wait([
>>>>>>> a53763d320be7b320454131c4120cbc49f48e947
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

<<<<<<< HEAD
=======
  /// Returns the Android SDK integer, or `0` on non-Android or error.
>>>>>>> a53763d320be7b320454131c4120cbc49f48e947
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
