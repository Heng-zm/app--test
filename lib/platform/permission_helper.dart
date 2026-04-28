import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'app_platform.dart';

// The conditional import resolves to the real package on mobile/desktop and
// falls back to the in-package web stub on dart:html (web) targets.
import 'package:permission_handler/permission_handler.dart'
    if (dart.library.html) 'package:bluetooth_chat/platform/permission_handler_web_stub.dart';

class PermissionHelper {
  PermissionHelper._();

  static final _deviceInfo = DeviceInfoPlugin();
  static int? _cachedAndroidSdk;

  // 🟢 FIX: Guard against concurrent calls to requestAllPermissions() from
  // racing each other (e.g. a fast double-tap on a retry button, or
  // didChangeAppLifecycleState re-entering while a dialog is still open).
  // A second call now waits for the first to complete and reuses its result.
  static Future<bool>? _ongoingRequest;

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Requests all necessary permissions in a single batch.
  /// Returns [true] if the app has sufficient rights to operate.
  static Future<bool> requestAllPermissions() {
    // 🟢 FIX: Deduplicate concurrent calls — callers share one in-flight
    // Future rather than each spawning their own system permission dialog.
    _ongoingRequest ??= _requestAllPermissionsImpl().whenComplete(() {
      _ongoingRequest = null;
    });
    return _ongoingRequest!;
  }

  static Future<bool> _requestAllPermissionsImpl() async {
    // 🟢 PERF: Immediate bypass for non-mobile platforms.
    if (kIsWeb || !AppPlatform.isMobile) return true;

    final int sdkInt = await _getAndroidSdk();
    final List<Permission> toRequest = _buildPermissionList(sdkInt);

    // ── 1. Parallel Status Check ─────────────────────────────────────────
    // 🟢 PERF: Fetch all statuses concurrently rather than sequentially.
    final statuses = await Future.wait(toRequest.map((p) => p.status));
    final List<Permission> actuallyNeeded = [
      for (int i = 0; i < toRequest.length; i++)
        if (!statuses[i].isGranted && !statuses[i].isLimited) toRequest[i],
    ];

    if (actuallyNeeded.isEmpty) return _validateCorePermissions(sdkInt);

    // ── 2. Batch Request ─────────────────────────────────────────────────
    try {
      await actuallyNeeded.request();
    } catch (e) {
      debugPrint('[Permissions] Request error: $e');
    }

    return _validateCorePermissions(sdkInt);
  }

  /// Non-blocking check for core permissions.
  /// Useful for UI updates without triggering system dialogs.
  static Future<bool> corePermissionsGranted() async =>
      _validateCorePermissions(await _getAndroidSdk());

  /// Checks if hardware radios (BT/GPS) are enabled at the system level.
  static Future<bool> areCoreServicesEnabled() async {
    if (kIsWeb || !AppPlatform.isMobile) return true;

    try {
      if (AppPlatform.isAndroid) {
        // 🟢 PERF: Concurrent hardware status check.
        final results = await Future.wait([
          Permission.bluetooth.serviceStatus,
          Permission.location.serviceStatus,
        ]);
        return results.every((s) => s.isEnabled);
      }

      if (AppPlatform.isIOS) {
        // iOS: Bluetooth status is handled by CoreBluetooth; check Location only.
        return (await Permission.location.serviceStatus).isEnabled;
      }
    } catch (_) {
      // Default to true to prevent blocking UI on OS errors.
      return true;
    }
    return true;
  }

  /// Returns [true] if the app can access the photo gallery.
  static Future<bool> hasPhotoPermission() async {
    if (kIsWeb || !AppPlatform.isMobile) return true;

    if (AppPlatform.isAndroid) {
      final sdk = await _getAndroidSdk();
      if (sdk >= 33) {
        // 🟢 PERF: Concurrent status check — previously called sequentially.
        final res = await Future.wait(
            [Permission.photos.status, Permission.videos.status]);
        return res.every((s) => s.isGranted || s.isLimited);
      }
      // 🟢 FIX: Use Permission.storage.status (a Future<PermissionStatus>)
      // instead of Permission.storage.isGranted (a Future<bool>) for
      // consistency. isGranted is a convenience wrapper but it swallows the
      // `isLimited` case that we handle everywhere else. Using `.status` and
      // checking both isGranted and isLimited is safer and consistent with the
      // rest of this file.
      final status = await Permission.storage.status;
      return status.isGranted || status.isLimited;
    }

    final iosStatus = await Permission.photos.status;
    return iosStatus.isGranted || iosStatus.isLimited;
  }

  /// Opens the system app settings screen.
  static Future<void> openSettings() => openAppSettings();

  // ─────────────────────────────────────────────────────────────────────────
  // Internal Helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Builds the full list of permissions to request for the current platform
  /// and SDK version.
  ///
  /// 🟢 REFACTOR: Extracted from _requestAllPermissionsImpl so the list can be
  /// unit-tested independently and reused in _validateCorePermissions without
  /// re-deriving the SDK level at the call site.
  static List<Permission> _buildPermissionList(int sdkInt) {
    final List<Permission> permissions = [];

    // ── Connectivity ──────────────────────────────────────────────────────
    if (AppPlatform.isAndroid) {
      permissions.add(Permission.location);
      if (sdkInt >= 31) {
        permissions.addAll([
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.bluetoothAdvertise,
        ]);
      }
      if (sdkInt >= 33) permissions.add(Permission.notification);
    } else if (AppPlatform.isIOS) {
      permissions.addAll([Permission.bluetooth, Permission.locationWhenInUse]);
    }

    // ── Media ─────────────────────────────────────────────────────────────
    permissions.addAll([Permission.camera, Permission.microphone]);
    if (AppPlatform.isAndroid) {
      if (sdkInt >= 33) {
        permissions.addAll([Permission.photos, Permission.videos]);
      } else {
        permissions.add(Permission.storage);
      }
    } else if (AppPlatform.isIOS) {
      permissions.add(Permission.photos);
    }

    return permissions;
  }

  static Future<bool> _validateCorePermissions(int sdkInt) async {
    if (kIsWeb || !AppPlatform.isMobile) return true;

    if (AppPlatform.isAndroid) {
      final List<Future<PermissionStatus>> core = [Permission.location.status];
      if (sdkInt >= 31) {
        core.addAll([
          Permission.bluetoothScan.status,
          Permission.bluetoothConnect.status,
        ]);
      }
      // 🟢 PERF: Already concurrent — preserved.
      final res = await Future.wait(core);
      return res.every((s) => s.isGranted || s.isLimited);
    }

    if (AppPlatform.isIOS) {
      final res = await Future.wait(
          [Permission.bluetooth.status, Permission.locationWhenInUse.status]);
      return res.every((s) => s.isGranted || s.isLimited);
    }

    return true;
  }

  static Future<int> _getAndroidSdk() async {
    if (!AppPlatform.isAndroid) return 0;
    // 🟢 PERF: Return cached value immediately — avoids a redundant platform
    // channel call on every subsequent invocation.
    if (_cachedAndroidSdk != null) return _cachedAndroidSdk!;

    try {
      final info = await _deviceInfo.androidInfo;
      return _cachedAndroidSdk = info.version.sdkInt;
    } catch (_) {
      // 🟢 FIX: Do NOT cache the fallback 0 here. If the DeviceInfoPlugin
      // call fails transiently (e.g. during startup race), caching 0 would
      // permanently suppress API-31+ Bluetooth permissions for the app's
      // lifetime. Return 0 without storing it so the next call retries.
      return 0;
    }
  }
}
