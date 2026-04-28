// Web stub for package:permission_handler/permission_handler.dart.
// Provides no-op implementations so that the file compiles on web targets
// where Bluetooth / location runtime permissions do not apply.

/// Stub [PermissionStatus] matching the mobile package API.
class PermissionStatus {
  const PermissionStatus._(this._value);
  final int _value;

  static const granted = PermissionStatus._(0);
  static const denied = PermissionStatus._(1);
  static const limited = PermissionStatus._(2);
  static const permanentlyDenied = PermissionStatus._(3);
  static const restricted = PermissionStatus._(4);
  static const provisional = PermissionStatus._(5);

  bool get isGranted => _value == 0;
  bool get isDenied => _value == 1;
  bool get isLimited => _value == 2;
  bool get isPermanentlyDenied => _value == 3;
  bool get isRestricted => _value == 4;
  bool get isProvisional => _value == 5;
}

/// Stub [ServiceStatus] matching the mobile package API.
class ServiceStatus {
  const ServiceStatus._(this._enabled);
  final bool _enabled;

  static const enabled = ServiceStatus._(true);
  static const disabled = ServiceStatus._(false);

  bool get isEnabled => _enabled;
  bool get isDisabled => !_enabled;
}

/// Stub [Permission] — all operations resolve instantly to 'granted' on Web.
class Permission {
  const Permission._(this.index);
  final int index;

  static const location = Permission._(0);
  static const locationWhenInUse = Permission._(1);
  static const locationAlways = Permission._(2);
  static const bluetooth = Permission._(3);
  static const bluetoothScan = Permission._(4);
  static const bluetoothConnect = Permission._(5);
  static const bluetoothAdvertise = Permission._(6);
  static const camera = Permission._(7);
  static const microphone = Permission._(8);
  static const photos = Permission._(9);
  static const videos = Permission._(10);
  static const storage = Permission._(11);
  static const notification = Permission._(12);

  /// Web: Always returns [PermissionStatus.granted]
  Future<PermissionStatus> get status async => PermissionStatus.granted;

  /// Web: Always returns [PermissionStatus.granted]
  Future<PermissionStatus> request() async => PermissionStatus.granted;

  /// Web: Always returns [ServiceStatus.enabled]
  Future<ServiceStatus> get serviceStatus async => ServiceStatus.enabled;

  /// Web: Always returns true
  Future<bool> get isGranted async => true;
}

/// Stub batch-request extension matching the mobile package behavior.
extension PermissionListStub on List<Permission> {
  Future<Map<Permission, PermissionStatus>> request() async {
    return Map.fromIterable(
      this,
      key: (p) => p as Permission,
      value: (_) => PermissionStatus.granted,
    );
  }
}

/// No-op — web targets do not have a system settings page for app permissions.
Future<bool> openAppSettings() async => false;
