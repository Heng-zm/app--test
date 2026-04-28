import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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
const String _kRxUuid = '6E400002-B5A3-F393-E0A9-E50E24DCCA9E';
const String _kTxUuid = '6E400003-B5A3-F393-E0A9-E50E24DCCA9E';

enum BtConnectionState { disconnected, scanning, connecting, connected, error }

class BluetoothService extends ChangeNotifier {
  final EncryptionService _encryption;
  final _uuid = const Uuid();
  ClassicBluetoothHelper? _classic;

  fbp.BluetoothDevice? _bleDevice;
  fbp.BluetoothCharacteristic? _bleWrite;

  StreamSubscription? _bleNotifySub;
  StreamSubscription? _bleScanSub;
  StreamSubscription? _bleAdapterSub;
  StreamSubscription? _isScanningSub; // Now properly cancelled
  StreamSubscription? _discoverySub;

  BtConnectionState _state = BtConnectionState.disconnected;
  final List<BTDevice> _pairedDevices = [];
  final List<BTDevice> _discovered = [];
  final List<Message> _messages = [];

  String? _connectedDeviceName;
  String? _errorMessage;

  bool _isDiscovering = false;
  bool _disposed = false;

  final BytesBuilder _byteBuffer = BytesBuilder();
  final _discoverySubject = PublishSubject<BTDevice>();

  BluetoothService({required EncryptionService encryption})
      : _encryption = encryption {
    if (!kIsWeb && AppPlatform.supportsClassicBluetooth) {
      _classic = ClassicBluetoothHelper();
    }

    _discoverySub = _discoverySubject
        .bufferTime(const Duration(milliseconds: 500))
        .where((list) => list.isNotEmpty)
        .listen(_addOrUpdateDiscoveredBatch);

    _bleAdapterSub = fbp.FlutterBluePlus.adapterState.listen((state) {
      if (state == fbp.BluetoothAdapterState.off) {
        disconnect();
      }
    });
  }

  // ── Initialization ──────────────────────────────────────

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
        onError: (e) => _setError('Classic Scan Error'),
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
                  : 'Unknown Node',
              address: r.device.remoteId.str,
              type: BTType.ble,
              rssi: r.rssi,
              isBLE: true,
            ));
          }
        });

        // Properly manage the scanning status subscription
        _isScanningSub?.cancel();
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
        if (_discovered[idx].rssi != d.rssi) {
          _discovered[idx] = d;
          changed = true;
        }
      } else {
        _discovered.add(d);
        changed = true;
      }
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
          onError: (_) => _setError('Radio Link Lost'),
        );
      } else {
        _bleDevice = fbp.BluetoothDevice.fromId(device.address);

        await _bleDevice!.connect(timeout: const Duration(seconds: 10));

        if (AppPlatform.isAndroid) {
          try {
            await _bleDevice!.requestMtu(512);
          } catch (_) {}
        }

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

        if (rx == null || tx == null) throw Exception('UART service missing');

        await tx.setNotifyValue(true);
        _bleNotifySub = tx.onValueReceived.listen(_onRawData);
        _bleWrite = rx;
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
    if (_byteBuffer.length > 10 * 1024 * 1024) _byteBuffer.clear();

    _byteBuffer.add(data);

    // 🟢 FIX: Use toBytes() instead of non-existent asUint8List()
    final Uint8List current = _byteBuffer.toBytes();
    int start = 0;

    while (true) {
      final int idx = current.indexOf(10, start);
      if (idx == -1) break;

      final packetBytes = current.sublist(start, idx);
      start = idx + 1;

      if (packetBytes.isEmpty) continue;

      final line = utf8.decode(packetBytes, allowMalformed: true).trim();

      if (line.length > 10000) {
        _processPacketInBg(line);
      } else {
        _processPacketSync(line);
      }
    }

    if (start > 0) {
      final remaining = current.sublist(start);
      _byteBuffer.clear();
      _byteBuffer.add(remaining);
    }
  }

  void _processPacketSync(String line) {
    final msg = _parseAndDecrypt(
        {'line': line, 'encryption': _encryption, 'uuid': _uuid.v4()});
    if (msg != null) {
      _messages.add(msg);
      _notify();
    }
  }

  Future<void> _processPacketInBg(String line) async {
    try {
      final Message? msg = await compute(_parseAndDecrypt, {
        'line': line,
        'encryption': _encryption,
        'uuid': _uuid.v4(),
      });
      if (msg != null && !_disposed) {
        _messages.add(msg);
        _notify();
      }
    } catch (_) {}
  }

  static Message? _parseAndDecrypt(Map<String, dynamic> args) {
    try {
      final String line = args['line'];
      final EncryptionService encryption = args['encryption'];
      final json = jsonDecode(line);
      final plain = encryption.decrypt(json['t'] as String);

      return Message(
        id: args['uuid'],
        text: plain,
        encryptedText: json['t'],
        isMine: false,
        timestamp: DateTime.now(),
        isImage: json['type'] == 'image',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> sendMessage(String text) async {
    final enc = _encryption.encrypt(text.trim());
    await _sendRawData({'type': 'text', 't': enc}, text.trim(), false);
  }

  Future<void> sendImage(Uint8List imageBytes) async {
    final base64String = base64Encode(imageBytes);
    final enc = _encryption.encrypt(base64String);
    await _sendRawData({'type': 'image', 't': enc}, base64String, true);
  }

  Future<void> _sendRawData(
      Map<String, String> data, String rawText, bool isImage) async {
    if (!isConnected) return;

    final packet = utf8.encode('${jsonEncode(data)}\n');

    try {
      if (_classic != null && _classic!.isConnected) {
        await _classic!.send(Uint8List.fromList(packet));
      } else if (_bleWrite != null) {
        final mtu = (_bleDevice?.mtuNow ?? 23) - 3;
        int chunkCount = 0;

        for (var i = 0; i < packet.length; i += mtu) {
          final end = (i + mtu < packet.length) ? i + mtu : packet.length;
          await _bleWrite!.write(packet.sublist(i, end), withoutResponse: true);

          chunkCount++;
          if (chunkCount % 10 == 0) {
            await Future.delayed(const Duration(milliseconds: 1));
          }
        }
      }

      _messages.add(Message(
        id: _uuid.v4(),
        text: rawText,
        encryptedText: isImage ? 'Image Data' : data['t']!,
        isMine: true,
        timestamp: DateTime.now(),
        isImage: isImage,
      ));
      _notify();
    } catch (_) {
      _setError('Transmission Failed');
    }
  }

  // ── Lifecycle ───────────────────────────────────────────

  Future<void> stopDiscovery() async {
    _isDiscovering = false;
    await _bleScanSub?.cancel();
    await _isScanningSub?.cancel(); // Cancel properly
    if (fbp.FlutterBluePlus.isScanningNow) await fbp.FlutterBluePlus.stopScan();
    _notify();
  }

  Future<void> disconnect() async {
    await _bleNotifySub?.cancel();
    await _isScanningSub?.cancel(); // Cancel properly
    if (_bleDevice != null) await _bleDevice!.disconnect();
    if (_classic != null) await _classic!.disconnect();

    _bleDevice = null;
    _bleWrite = null;
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
    _bleAdapterSub?.cancel();
    _isScanningSub?.cancel(); // Cancel properly
    _discoverySubject.close();
    disconnect();
    super.dispose();
  }
}
