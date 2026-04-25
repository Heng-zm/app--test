import 'dart:io';
import 'package:flutter/foundation.dart';

/// Central platform detection used throughout the app.
/// Optimized with static final constants for performance.
class AppPlatform {
  AppPlatform._();

  static final bool isWeb = kIsWeb;

  // Platform checks (Evaluated once at startup)
  static final bool isAndroid = !kIsWeb && Platform.isAndroid;
  static final bool isIOS = !kIsWeb && Platform.isIOS;
  static final bool isMacOS = !kIsWeb && Platform.isMacOS;
  static final bool isWindows = !kIsWeb && Platform.isWindows;
  static final bool isLinux = !kIsWeb && Platform.isLinux;
  static final bool isFuchsia = !kIsWeb && Platform.isFuchsia;

  // Aggregated platform groups
  static final bool isMobile = isAndroid || isIOS;
  static final bool isDesktop = isMacOS || isWindows || isLinux;

  /// Supports Bluetooth Classic SPP.
  /// flutter_bluetooth_serial is currently Android-only for your project.
  static final bool supportsClassicBluetooth = isAndroid;

  /// Supports BLE (Bluetooth Low Energy).
  /// Based on flutter_blue_plus compatibility.
  static final bool supportsBLE =
      isAndroid || isIOS || isMacOS || isWindows || isLinux;

  /// Whether we need to request runtime permissions (Location/BT/Camera).
  /// Desktop platforms usually handle this via Info.plist/Manifest or system dialogs on-demand.
  static final bool needsRuntimePermissions = isMobile;

  /// Returns the string representation of the current platform.
  static final String name = _getPlatformName();

  static String _getPlatformName() {
    if (isWeb) return 'Web';
    if (isAndroid) return 'Android';
    if (isIOS) return 'iOS';
    if (isMacOS) return 'macOS';
    if (isWindows) return 'Windows';
    if (isLinux) return 'Linux';
    if (isFuchsia) return 'Fuchsia';
    return 'Unknown';
  }

  /// 🛠️ NEW: Helps handle UI scaling for different environments
  static bool get isSmallScreen => isMobile;
}
