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

// Nordic UART UUIDs
const String _kServiceUuid = '6E400001-B5A3-F393-E0A9-E50E24DCCA9E';
const String _kTxUuid = '6E400003-B5A3-F393-E0A9-E50E24DCCA9E';
const String _kRxUuid = '6E400002-B5A3-F393-E0A9-E50E24DCCA9E';

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
  StreamSubscription? _isScanningSub;
  StreamSubscription? _discoverySub; // Added cleanup

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

  BluetoothService({required EncryptionService encryption})
      : _encryption = encryption {
    if (!kIsWeb && AppPlatform.supportsClassicBluetooth) {
      _classic = ClassicBluetoothHelper();
    }

    _discoverySub = _discoverySubject
        .bufferTime(const Duration(milliseconds: 400))
        .where((list) => list.isNotEmpty)
        .listen(_addOrUpdateDiscoveredBatch);
  }

  // ── Added Missing Methods ───────────────────────────────

  Future<void> initialize() async {
    if (kIsWeb) return;
    try {
      if (AppPlatform.supportsClassicBluetooth && _classic != null) {
        await _classic!.ensureEnabled();
        final pairs = await _classic!.getBondedDevices();
        _pairedDevices.clear();
        _pairedDevices.addAll(pairs);
      }
      _notify();
    } catch (_) {}
  }

  void updatePassphrase(String passphrase) {
    _encryption.updatePassphrase(passphrase);
    _notify();
  }

  void clearMessages() {
    _messages.clear();
    _notify();
  }

  // ── Getters ─────────────────────────────────────────────
  BtConnectionState get state => _state;
  List<BTDevice> get pairedDevices => List.unmodifiable(_pairedDevices);
  List<BTDevice> get discovered => List.unmodifiable(_discovered);
  List<Message> get messages => List.unmodifiable(_messages);
  bool get isConnected => _state == BtConnectionState.connected;
  bool get isDiscovering => _isDiscovering;
  String? get connectedDeviceName => _connectedDeviceName;
  String? get errorMessage => _errorMessage;

  // ── Discovery ───────────────────────────────────────────
  Future<void> startDiscovery() async {
    if (kIsWeb) return;
    if (_isDiscovering) await stopDiscovery();

    _discovered.clear();
    _isDiscovering = true;
    _setState(BtConnectionState.scanning);

    if (AppPlatform.supportsClassicBluetooth && _classic != null) {
      _classic!.startDiscovery(
        onFound: (d) => _discoverySubject.add(d),
        onDone: () => _stopScanUI(),
        onError: (e) => _setError('Scan Error'),
      );
    }

    if (AppPlatform.supportsBLE) {
      try {
        await fbp.FlutterBluePlus.startScan(
            timeout: const Duration(seconds: 15));
        _bleScanSub = fbp.FlutterBluePlus.scanResults.listen((results) {
          for (final r in results) {
            _discoverySubject.add(BTDevice(
              name: r.device.platformName.isNotEmpty
                  ? r.device.platformName
                  : 'Unknown',
              address: r.device.remoteId.str,
              type: 'BLE',
              rssi: r.rssi,
              isBLE: true,
            ));
          }
        });
        _isScanningSub = fbp.FlutterBluePlus.isScanning.listen((isScanning) {
          if (!isScanning && _isDiscovering) _stopScanUI();
        });
      } catch (_) {
        _stopScanUI();
      }
    }
  }

  void _addOrUpdateDiscoveredBatch(List<BTDevice> devices) {
    bool changed = false;
    for (final d in devices) {
      final idx = _discovered.indexWhere((x) => x.address == d.address);
      if (idx >= 0) {
        _discovered[idx] = d;
      } else {
        _discovered.add(d);
      }
      changed = true;
    }
    if (changed) {
      _discovered.sort((a, b) => (b.rssi ?? -100).compareTo(a.rssi ?? -100));
      _notify();
    }
  }

  // ── Connection Logic ────────────────────────────────────
  Future<void> connectToDevice(BTDevice device) async {
    if (kIsWeb || _state == BtConnectionState.connecting) return;
    await stopDiscovery();
    await disconnect();
    _setState(BtConnectionState.connecting);

    try {
      if (!device.isBLE && _classic != null) {
        await _classic!.connect(
          address: device.address,
          onData: _onRawData,
          onDone: disconnect,
          onError: (_) => _setError('Link Lost'),
        );
      } else {
        _bleDevice = fbp.BluetoothDevice.fromId(device.address);
        await _bleDevice!.connect(timeout: const Duration(seconds: 10));

        final services = await _bleDevice!.discoverServices();
        fbp.BluetoothCharacteristic? rx;
        fbp.BluetoothCharacteristic? tx;

        for (var s in services) {
          if (s.uuid.toString().toUpperCase() == _kServiceUuid) {
            for (var c in s.characteristics) {
              if (c.uuid.toString().toUpperCase() == _kRxUuid) rx = c;
              if (c.uuid.toString().toUpperCase() == _kTxUuid) tx = c;
            }
          }
        }

        if (rx == null || tx == null) throw Exception();

        await tx.setNotifyValue(true);
        _bleNotifySub = tx.onValueReceived.listen(_onRawData);
        _bleRx = rx;
      }

      _connectedDeviceName = device.name;
      _setState(BtConnectionState.connected);
    } catch (e) {
      await disconnect();
      _setError('Link Failed');
    }
  }

  // ── Messaging ───────────────────────────────────────────
  void _onRawData(List<int> data) {
    _byteBuffer.addAll(data);
    while (true) {
      int idx = _byteBuffer.indexOf(10);
      if (idx == -1) break;
      final line =
          utf8.decode(_byteBuffer.sublist(0, idx), allowMalformed: true).trim();
      _byteBuffer.removeRange(0, idx + 1);
      if (line.isNotEmpty) _processPacket(line);
    }
  }

  void _processPacket(String line) {
    try {
      final json = jsonDecode(line);
      final plain = _encryption.decrypt(json['t']);
      _messages.add(Message(
        id: _uuid.v4(),
        text: plain,
        encryptedText: json['t'],
        isMine: false,
        timestamp: DateTime.now(),
        isImage: json['type'] == 'image',
      ));
      _notify();
    } catch (_) {}
  }

  Future<void> sendMessage(String text) async {
    if (!isConnected) return;
    final enc = _encryption.encrypt(text.trim());
    final packet = utf8.encode('${jsonEncode({'type': 'text', 't': enc})}\n');
    try {
      if (_classic != null && _classic!.isConnected) {
        await _classic!.send(Uint8List.fromList(packet));
      } else if (_bleRx != null) {
        final mtu = (_bleDevice?.mtuNow ?? 23) - 3;
        for (var i = 0; i < packet.length; i += mtu) {
          final end = (i + mtu < packet.length) ? i + mtu : packet.length;
          await _bleRx!.write(packet.sublist(i, end), withoutResponse: true);
        }
      }
      _messages.add(Message(
        id: _uuid.v4(),
        text: text.trim(),
        encryptedText: enc,
        isMine: true,
        timestamp: DateTime.now(),
      ));
      _notify();
    } catch (_) {}
  }

  // ── Lifecycle ───────────────────────────────────────────
  Future<void> stopDiscovery() async {
    _isDiscovering = false;
    await _bleScanSub?.cancel();
    if (fbp.FlutterBluePlus.isScanningNow) await fbp.FlutterBluePlus.stopScan();
    _notify();
  }

  Future<void> disconnect() async {
    await _bleNotifySub?.cancel();
    await _bleStateSub?.cancel();
    await _isScanningSub?.cancel();
    if (_bleDevice != null) await _bleDevice!.disconnect();
    if (_classic != null) await _classic!.disconnect();
    _bleDevice = null;
    _bleRx = null;
    _byteBuffer.clear();
    _connectedDeviceName = null;
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
    if (!_disposed) notifyListeners();
  }

  void _stopScanUI() {
    _isDiscovering = false;
    _notify();
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
