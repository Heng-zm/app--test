import 'dart:typed_data';
import '../models/device_model.dart';

/// Placeholder for non-Android platforms.
class ClassicBluetoothHelper {
  bool get isConnected => false;

  Future<void> ensureEnabled() async {}

  Future<List<BTDevice>> getBondedDevices() async => [];

  void startDiscovery({
    required void Function(BTDevice) onFound,
    required void Function() onDone,
    required void Function(dynamic) onError,
  }) {
    onDone();
  }

  Future<void> cancelDiscovery() async {}

  Future<void> connect({
    required String address,
    required void Function(List<int>) onData,
    required void Function() onDone,
    required void Function(dynamic) onError,
  }) async {
    throw UnsupportedError('Classic BT is Android-only.');
  }

  Future<void> send(Uint8List data) async {}
  Future<void> disconnect() async {}
  void dispose() {}
}
