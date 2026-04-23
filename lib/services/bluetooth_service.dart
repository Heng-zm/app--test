import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';
import '../platform/app_platform.dart';
import 'encryption_service.dart';
import '../models/message_model.dart';
import '../models/device_model.dart';

import 'bluetooth_classic_stub.dart'
    if (dart.library.io) 'bluetooth_classic_android.dart';

const _kTxUuid = '6E400003-B5A3-F393-E0A9-E50E24DCCA9E';
const _kRxUuid = '6E400002-B5A3-F393-E0A9-E50E24DCCA9E';

enum BtConnectionState { disconnected, scanning, connecting, connected, error }

class BluetoothService extends ChangeNotifier {
  final EncryptionService _encryption;
  final _uuid = const Uuid();
  ClassicBluetoothHelper? _classic;

  fbp.BluetoothDevice? _bleDevice;
  fbp.BluetoothCharacteristic? _bleRx;
  StreamSubscription? _bleNotifySub;
  StreamSubscription? _bleScanSub;
  StreamSubscription? _bleStateSub;

  BtConnectionState _state = BtConnectionState.disconnected;
  final List<BTDevice> _pairedDevices = [];
  final List<BTDevice> _discovered = [];
  final List<Message> _messages = [];
  String? _connectedDeviceName;
  String? _errorMessage;
  bool _isDiscovering = false;
  bool _disposed = false;

  final List<int> _byteBuffer = [];
  final _discoverySubject = PublishSubject<BTDevice>();
  StreamSubscription? _discoverySub;

  BluetoothService({required EncryptionService encryption})
      : _encryption = encryption {
    if (AppPlatform.supportsClassicBluetooth) {
      _classic = ClassicBluetoothHelper();
    }
    _discoverySub = _discoverySubject
        .throttleTime(const Duration(milliseconds: 250))
        .listen(_addOrUpdateDiscovered);
  }

  BtConnectionState get state => _state;
  List<BTDevice> get discovered {
    final list = List<BTDevice>.from(_discovered);
    list.sort((a, b) => (b.rssi ?? -100).compareTo(a.rssi ?? -100));
    return List.unmodifiable(list);
  }

  List<BTDevice> get pairedDevices => List.unmodifiable(_pairedDevices);
  List<Message> get messages => List.unmodifiable(_messages);
  bool get isConnected => _state == BtConnectionState.connected;
  bool get isDiscovering => _isDiscovering;
  String? get connectedDeviceName => _connectedDeviceName;
  String? get errorMessage => _errorMessage;

  Future<void> initialize() async {
    try {
      if (AppPlatform.supportsClassicBluetooth) {
        await _classic!.ensureEnabled();
        final pairs = await _classic!.getBondedDevices();
        _pairedDevices
          ..clear()
          ..addAll(pairs);
      }
      if (AppPlatform.supportsBLE) {
        final st = await fbp.FlutterBluePlus.adapterState.first;
        if (st != fbp.BluetoothAdapterState.on && AppPlatform.isAndroid) {
          await fbp.FlutterBluePlus.turnOn();
        }
      }
      _notify();
    } catch (e) {
      _setError('Initialization failed: $e');
    }
  }

  Future<void> startDiscovery() async {
    if (_isDiscovering) {
      await stopDiscovery();
    }
    _discovered.clear();
    _isDiscovering = true;
    _setState(BtConnectionState.scanning);

    if (AppPlatform.supportsBLE) {
      try {
        await fbp.FlutterBluePlus.startScan(
            timeout: const Duration(seconds: 15));
        _bleScanSub = fbp.FlutterBluePlus.scanResults.listen((results) {
          for (final r in results) {
            _discoverySubject.add(BTDevice(
              name: r.device.platformName.isNotEmpty
                  ? r.device.platformName
                  : 'Target Node',
              address: r.device.remoteId.str,
              type: 'BLE',
              rssi: r.rssi,
              isBLE: true,
            ));
          }
        });
        fbp.FlutterBluePlus.isScanning
            .where((s) => !s)
            .first
            .then((_) => _stopScanUI());
      } catch (e) {
        _setError('BLE scan error: $e');
        _stopScanUI();
      }
    }
  }

  void _stopScanUI() {
    _isDiscovering = false;
    if (_state == BtConnectionState.scanning) {
      _setState(BtConnectionState.disconnected);
    }
    _notify();
  }

  Future<void> stopDiscovery() async {
    await _bleScanSub?.cancel();
    if (fbp.FlutterBluePlus.isScanningNow) {
      await fbp.FlutterBluePlus.stopScan();
    }
    _stopScanUI();
  }

  void _addOrUpdateDiscovered(BTDevice d) {
    final idx = _discovered.indexWhere((x) => x.address == d.address);
    if (idx >= 0) {
      _discovered[idx] = d;
    } else {
      _discovered.add(d);
    }
    _notify();
  }

  Future<void> connectToDevice(BTDevice device) async {
    if (_state == BtConnectionState.connecting) {
      return;
    }
    await stopDiscovery();
    await disconnect();
    _setState(BtConnectionState.connecting);
    _messages.clear();

    try {
      if (device.isBLE) {
        _bleDevice = fbp.BluetoothDevice.fromId(device.address);
        await _bleDevice!.connect(timeout: const Duration(seconds: 15));
        if (AppPlatform.isAndroid) {
          await _bleDevice!.requestMtu(512);
        }
        final svcs = await _bleDevice!.discoverServices();
        for (var s in svcs) {
          for (var c in s.characteristics) {
            if (c.uuid.toString().toUpperCase() == _kRxUuid) {
              _bleRx = c;
            }
            if (c.uuid.toString().toUpperCase() == _kTxUuid) {
              await c.setNotifyValue(true);
              _bleNotifySub = c.onValueReceived.listen(_onRawData);
            }
          }
        }
        if (_bleRx == null) {
          throw Exception('Protocol Mismatch');
        }
      }
      _connectedDeviceName = device.name;
      _setState(BtConnectionState.connected);
    } catch (e) {
      await disconnect();
      _setError('Link failed: $e');
    }
  }

  void _onRawData(List<int> data) {
    _byteBuffer.addAll(data);
    while (_byteBuffer.contains(10)) {
      final idx = _byteBuffer.indexOf(10);
      try {
        final line = utf8
            .decode(_byteBuffer.sublist(0, idx), allowMalformed: true)
            .trim();
        _byteBuffer.removeRange(0, idx + 1);
        if (line.isNotEmpty) {
          _parsePacket(line);
        }
      } catch (e) {
        _byteBuffer.removeRange(0, idx + 1);
      }
    }
  }

  void _parsePacket(String line) {
    try {
      final json = jsonDecode(line) as Map<String, dynamic>;
      final cipher = json['t'] as String? ?? '';
      final plain = _encryption.decrypt(cipher);
      _messages.add(Message(
          id: _uuid.v4(),
          text: plain,
          encryptedText: cipher,
          isMine: false,
          timestamp: DateTime.now()));
    } catch (_) {
      _messages.add(Message(
          id: _uuid.v4(),
          text: 'Decryption Error: $line',
          encryptedText: line,
          isMine: false,
          timestamp: DateTime.now(),
          isDecryptionError: true));
    }
    _notify();
  }

  Future<void> sendMessage(String text) async {
    if (!isConnected || text.trim().isEmpty) {
      return;
    }
    final enc = _encryption.encrypt(text.trim());
    final packet = utf8.encode('${jsonEncode({'t': enc})}\n');

    try {
      if (_bleRx != null) {
        int mtu = (_bleDevice?.mtuNow ?? 23) - 3;
        for (var i = 0; i < packet.length; i += mtu) {
          final end = (i + mtu < packet.length) ? i + mtu : packet.length;
          await _bleRx!.write(packet.sublist(i, end), withoutResponse: true);
        }
      }
      _messages.add(Message(
          id: _uuid.v4(),
          text: text,
          encryptedText: enc,
          isMine: true,
          timestamp: DateTime.now()));
      _notify();
    } catch (e) {
      _setError('Send failed: $e');
    }
  }

  void clearMessages() {
    _messages.clear();
    _notify();
  }

  void clearError() {
    _errorMessage = null;
    if (_state == BtConnectionState.error) {
      _state = BtConnectionState.disconnected;
    }
    _notify();
  }

  void updatePassphrase(String p) => _encryption.updatePassphrase(p);

  Future<void> disconnect() async {
    await _bleNotifySub?.cancel();
    await _bleStateSub?.cancel();
    if (_bleDevice != null) {
      await _bleDevice!.disconnect();
    }
    _bleDevice = null;
    _bleRx = null;
    _byteBuffer.clear();
    _setState(BtConnectionState.disconnected);
  }

  void _setState(BtConnectionState s) {
    _state = s;
    _errorMessage = null;
    _notify();
  }

  void _setError(String m) {
    _errorMessage = m;
    _state = BtConnectionState.error;
    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _discoverySub?.cancel();
    _discoverySubject.close();
    disconnect();
    super.dispose();
  }
}
