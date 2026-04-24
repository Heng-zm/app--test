import 'package:flutter/foundation.dart';
import '../platform/app_platform.dart';

// ✅ permission_handler is only imported on non-web targets.
// On web this resolves to a no-op stub (dart.library.html = web).
import 'package:permission_handler/permission_handler.dart'
    if (dart.library.html) 'permission_handler_web_stub.dart';

/// Requests all Bluetooth and location permissions required by the app.
/// Safe to call on all platforms — silently skips on web and desktop.
Future<void> requestPermissions() async {
  // Web: permission_handler is not supported
  if (kIsWeb) return;

  // Desktop (Windows, macOS, Linux): no runtime permissions needed
  if (AppPlatform.isDesktop) return;

  // Mobile only from here (Android + iOS)
  if (AppPlatform.isAndroid) {
    await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
    await Permission.bluetoothAdvertise.request();
    await Permission.location.request();
  }

  if (AppPlatform.isIOS) {
    await Permission.bluetooth.request();
    await Permission.locationWhenInUse.request();
  }
}
