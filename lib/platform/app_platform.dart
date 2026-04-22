import 'dart:io';
import 'package:flutter/foundation.dart';

/// Central platform detection used throughout the app.
/// Avoids dart:io on Web (which throws) by checking kIsWeb first.
class AppPlatform {
  AppPlatform._();

  static bool get isWeb => kIsWeb;
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get isIOS => !kIsWeb && Platform.isIOS;
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;
  static bool get isWindows => !kIsWeb && Platform.isWindows;
  static bool get isLinux => !kIsWeb && Platform.isLinux;
  static bool get isFuchsia => !kIsWeb && Platform.isFuchsia;

  static bool get isMobile => isAndroid || isIOS;
  static bool get isDesktop => isMacOS || isWindows || isLinux;

  /// Supports Bluetooth Classic SPP (only real Android hardware).
  static bool get supportsClassicBluetooth => isAndroid;

  /// Supports BLE on all platforms except Fuchsia and Web (best effort).
  static bool get supportsBLE =>
      isAndroid || isIOS || isMacOS || isWindows || isLinux;

  /// Whether we need to request runtime permissions.
  static bool get needsRuntimePermissions => isMobile;

  static String get name {
    if (isWeb) return 'Web';
    if (isAndroid) return 'Android';
    if (isIOS) return 'iOS';
    if (isMacOS) return 'macOS';
    if (isWindows) return 'Windows';
    if (isLinux) return 'Linux';
    return 'Unknown';
  }
}
