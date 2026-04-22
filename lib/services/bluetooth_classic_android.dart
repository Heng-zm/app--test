import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import '../models/device_model.dart';

/// Wraps flutter_bluetooth_serial for Bluetooth Classic (SPP) on Android.
/// Compiled only when dart.library.io is available AND platform is Android
/// (enforced via the conditional import in bluetooth_service.dart).
class ClassicBluetoothHelper {
  BluetoothConnection? _connection;
  StreamSubscription? _inputSub;
  StreamSubscription? _discoverySub;

  bool get isConnected => _connection?.isConnected ?? false;

  Future<void> ensureEnabled() async {
    final enabled = await FlutterBluetoothSerial.instance.isEnabled ?? false;
    if (!enabled) {
      await FlutterBluetoothSerial.instance.requestEnable();
    }
  }

  Future<List<BTDevice>> getBondedDevices() async {
    final bonded = await FlutterBluetoothSerial.instance.getBondedDevices();
    return bonded
        .map((d) => BTDevice(
              name: d.name?.isNotEmpty == true ? d.name! : 'Unknown',
              address: d.address,
              type: _typeLabel(d.type),
              isPaired: true,
              isBLE: d.type == BluetoothDeviceType.le,
            ))
        .toList();
  }

  void startDiscovery({
    required void Function(BTDevice) onFound,
    required void Function() onDone,
    required void Function(dynamic) onError,
  }) {
    _discoverySub?.cancel();
    _discoverySub = FlutterBluetoothSerial.instance.startDiscovery().listen(
      (r) {
        onFound(BTDevice(
          name: r.device.name?.isNotEmpty == true ? r.device.name! : 'Unknown',
          address: r.device.address,
          type: _typeLabel(r.device.type),
          rssi: r.rssi,
          isPaired: r.device.isBonded,
          isBLE: r.device.type == BluetoothDeviceType.le,
        ));
      },
      onDone: onDone,
      onError: onError,
      cancelOnError: false,
    );
  }

  Future<void> cancelDiscovery() async {
    await _discoverySub?.cancel();
    _discoverySub = null;
    await FlutterBluetoothSerial.instance.cancelDiscovery();
  }

  Future<void> connect({
    required String address,
    required void Function(List<int>) onData,
    required void Function() onDone,
    required void Function(dynamic) onError,
  }) async {
    _connection = await BluetoothConnection.toAddress(address);

    _inputSub = _connection!.input!.listen(
      (data) => onData(data),
      onDone: onDone,
      onError: onError,
      cancelOnError: false,
    );
  }

  Future<void> send(Uint8List data) async {
    _connection?.output.add(data);
    await _connection?.output.allSent;
  }

  Future<void> disconnect() async {
    await _inputSub?.cancel();
    _inputSub = null;
    await _connection?.close();
    _connection = null;
  }

  void dispose() {
    _discoverySub?.cancel();
    _inputSub?.cancel();
    _connection?.close();
  }

  static String _typeLabel(BluetoothDeviceType t) {
    switch (t) {
      case BluetoothDeviceType.classic: return 'Classic';
      case BluetoothDeviceType.le:      return 'BLE';
      case BluetoothDeviceType.dual:    return 'Dual';
      default:                          return 'Unknown';
    }
  }
}
