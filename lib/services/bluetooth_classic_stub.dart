import 'dart:typed_data';
import '../models/device_model.dart';

/// No-op stub used on iOS, macOS, Windows, Linux, Web.
/// The real implementation lives in bluetooth_classic_android.dart and is
/// only compiled on Android.
class ClassicBluetoothHelper {
  bool get isConnected => false;

  Future<void> ensureEnabled() async {}

  Future<List<BTDevice>> getBondedDevices() async => [];

  void startDiscovery({
    required void Function(BTDevice) onFound,
    required void Function() onDone,
    required void Function(dynamic) onError,
  }) {}

  Future<void> cancelDiscovery() async {}

  Future<void> connect({
    required String address,
    required void Function(List<int>) onData,
    required void Function() onDone,
    required void Function(dynamic) onError,
  }) async {
    throw UnsupportedError(
      'Bluetooth Classic is only available on Android. '
      'Use BLE on this platform.',
    );
  }

  Future<void> send(Uint8List data) async {}
  Future<void> disconnect() async {}
  void dispose() {}
}
