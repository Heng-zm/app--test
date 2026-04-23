import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import '../models/device_model.dart';

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
              name: d.name ?? 'Unknown',
              address: d.address,
              type: 'Classic',
              isPaired: true,
              isBLE: false,
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
          name: r.device.name ?? 'Unknown',
          address: r.device.address,
          type: 'Classic',
          rssi: r.rssi,
          isPaired: r.device.isBonded,
          isBLE: false,
        ));
      },
      onDone: onDone,
      onError: onError,
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
      onData,
      onDone: onDone,
      onError: onError,
    );
  }

  Future<void> send(Uint8List data) async {
    if (_connection != null && _connection!.isConnected) {
      _connection!.output.add(data);
      await _connection!.output.allSent;
    }
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
}
