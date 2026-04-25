import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import '../models/device_model.dart';

class ClassicBluetoothHelper {
  BluetoothConnection? _connection;
  StreamSubscription? _inputSub;
  StreamSubscription? _discoverySub;

  bool get isConnected => _connection?.isConnected ?? false;

  /// Ensures Bluetooth radio is active.
  Future<bool> ensureEnabled() async {
    try {
      final enabled = await FlutterBluetoothSerial.instance.isEnabled ?? false;
      if (!enabled) {
        return await FlutterBluetoothSerial.instance.requestEnable() ?? false;
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Fetches bonded (paired) devices from the OS.
  Future<List<BTDevice>> getBondedDevices() async {
    try {
      final bonded = await FlutterBluetoothSerial.instance.getBondedDevices();
      return bonded
          .map((d) => BTDevice(
                name: d.name ?? 'Unknown Device',
                address: d.address,
                type: BTType.classic, // 🛠️ Using optimized Enum
                isPaired: true,
                isBLE: false,
              ))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Starts scanning for nearby Classic BT devices.
  void startDiscovery({
    required void Function(BTDevice) onFound,
    required void Function() onDone,
    required void Function(dynamic) onError,
  }) {
    // 🛠️ PERF: Cancel any existing discovery before starting a new one
    _discoverySub?.cancel();

    _discoverySub = FlutterBluetoothSerial.instance.startDiscovery().listen(
      (r) {
        onFound(BTDevice(
          name: r.device.name ?? 'Unknown',
          address: r.device.address,
          type: BTType.classic,
          rssi: r.rssi,
          isPaired: r.device.isBonded,
          isBLE: false,
        ));
      },
      onDone: onDone,
      onError: onError,
    );
  }

  /// Stops the active discovery process.
  Future<void> cancelDiscovery() async {
    await _discoverySub?.cancel();
    _discoverySub = null;
    try {
      await FlutterBluetoothSerial.instance.cancelDiscovery();
    } catch (_) {}
  }

  /// Establishes an RFCOMM connection to the specified address.
  Future<void> connect({
    required String address,
    required void Function(List<int>) onData,
    required void Function() onDone,
    required void Function(dynamic) onError,
  }) async {
    // 🛠️ FIX: Ensure previous connection is fully closed before starting a new one
    if (isConnected) await disconnect();

    try {
      _connection = await BluetoothConnection.toAddress(address);

      _inputSub = _connection!.input!.listen(
        onData,
        onDone: () {
          disconnect();
          onDone();
        },
        onError: (e) {
          disconnect();
          onError(e);
        },
      );
    } catch (e) {
      await disconnect();
      rethrow;
    }
  }

  /// Sends raw bytes over the SPP link.
  Future<void> send(Uint8List data) async {
    final conn = _connection;
    if (conn != null && conn.isConnected) {
      try {
        conn.output.add(data);
        await conn.output.allSent;
      } catch (e) {
        await disconnect();
        rethrow;
      }
    }
  }

  /// Gracefully closes the connection and cancels listeners.
  Future<void> disconnect() async {
    // 🛠️ FIX: Cancel input stream BEFORE closing the connection to avoid "Read Error"
    await _inputSub?.cancel();
    _inputSub = null;

    if (_connection != null) {
      try {
        await _connection!.finish(); // Use finish() for graceful closure
        _connection!.dispose();
      } catch (_) {}
      _connection = null;
    }
  }

  /// Full cleanup for service disposal.
  void dispose() {
    _discoverySub?.cancel();
    disconnect();
  }
}
