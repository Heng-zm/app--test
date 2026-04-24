/// Web stub for permission_handler.
/// This file is imported instead of package:permission_handler on web builds.
/// All classes and methods are no-ops so the app compiles cleanly on web.

class Permission {
  const Permission._();

  static const Permission bluetooth = Permission._();
  static const Permission bluetoothScan = Permission._();
  static const Permission bluetoothConnect = Permission._();
  static const Permission bluetoothAdvertise = Permission._();
  static const Permission location = Permission._();
  static const Permission locationWhenInUse = Permission._();
  static const Permission camera = Permission._();
  static const Permission microphone = Permission._();
  static const Permission photos = Permission._();

  Future<PermissionStatus> request() async => PermissionStatus.granted;
}

class PermissionStatus {
  final String _value;
  const PermissionStatus._(this._value);

  static const PermissionStatus granted = PermissionStatus._('granted');
  static const PermissionStatus denied = PermissionStatus._('denied');

  bool get isGranted => _value == 'granted';
  bool get isDenied => _value == 'denied';
  bool get isLimited => false;
  bool get isPermanentlyDenied => false;

  @override
  String toString() => _value;
}

Future<void> openAppSettings() async {}
