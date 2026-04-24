import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
// ✅ Guard dart:io — not available on web
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';

import '../platform/app_platform.dart';
import 'encryption_service.dart';
import '../models/message_model.dart';
import '../models/device_model.dart';

// Conditional import to handle non-Android platforms safely
import 'bluetooth_classic_stub.dart'
    if (dart.library.io) 'bluetooth_classic_android.dart';

// UUIDs for the Nordic UART Service (Standard for serial-over-BLE)
const _kServiceUuid = '6E400001-B5A3-F393-E0A9-E50E24DCCA9E';
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
  StreamSubscription?
      _isScanningSub; // 🛠️ FIX: Tracked to prevent memory leaks

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
    if (!kIsWeb && AppPlatform.supportsClassicBluetooth) {
      _classic = ClassicBluetoothHelper();
    }

    // 🛠️ FIX & PERF: Changed `throttleTime` to `bufferTime`.
    // throttleTime DROPS events that arrive closely together, causing you to miss scanned devices.
    // bufferTime collects them into a batch and emits them every 250ms safely.
    _discoverySub = _discoverySubject
        .bufferTime(const Duration(milliseconds: 250))
        .where((list) => list.isNotEmpty)
        .listen(_addOrUpdateDiscoveredBatch);
  }

  // ── Getters ─────────────────────────────────────────────

  BtConnectionState get state => _state;
  List<BTDevice> get pairedDevices => List.unmodifiable(_pairedDevices);

  // 🛠️ PERF: Removed sorting from the getter.
  // Sorting here forces an O(N log N) operation EVERY time the UI rebuilds.
  // Sorting is now handled once during the discovery buffered stream.
  List<BTDevice> get discovered => List.unmodifiable(_discovered);

  List<Message> get messages => List.unmodifiable(_messages);
  bool get isConnected => _state == BtConnectionState.connected;
  bool get isDiscovering => _isDiscovering;
  String? get connectedDeviceName => _connectedDeviceName;
  String? get errorMessage => _errorMessage;

  // ── Initialization ──────────────────────────────────────

  Future<void> initialize() async {
    if (kIsWeb) return;

    try {
      if (!kIsWeb) {
        await _initNative();
      }
      _notify();
    } catch (e) {
      _setError('Initialization failed: $e');
    }
  }

  Future<void> _initNative() async {
    try {
      if (AppPlatform.supportsClassicBluetooth && _classic != null) {
        await _classic!.ensureEnabled();
        final pairs = await _classic!.getBondedDevices();
        _pairedDevices
          ..clear()
          ..addAll(pairs);
      }

      if (AppPlatform.supportsBLE) {
        final adapterState = await fbp.FlutterBluePlus.adapterState.first;
        if (adapterState != fbp.BluetoothAdapterState.on &&
            AppPlatform.isAndroid) {
          await fbp.FlutterBluePlus.turnOn();
        }
      }
    } catch (e) {
      rethrow;
    }
  }

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
        onDone: () {
          if (!AppPlatform.supportsBLE) _stopScanUI();
        },
        onError: (e) => _setError('Classic scan error: $e'),
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
                  : 'Unknown Device',
              address: r.device.remoteId.str,
              type: 'BLE',
              rssi: r.rssi,
              isBLE: true,
            ));
          }
        });

        // 🛠️ FIX: Previously this used `.first`, which creates hanging futures if stopped early.
        // Listening properly ensures accurate cleanup.
        _isScanningSub?.cancel();
        _isScanningSub = fbp.FlutterBluePlus.isScanning.listen((isScanning) {
          if (!isScanning && _isDiscovering) {
            _stopScanUI();
          }
        });
      } catch (e) {
        _setError('BLE scan error: $e');
        _stopScanUI();
      }
    }
  }

  void _stopScanUI() {
    if (!_isDiscovering) return;
    _isDiscovering = false;
    if (_state == BtConnectionState.scanning) {
      _setState(BtConnectionState.disconnected);
    }
  }

  Future<void> stopDiscovery() async {
    if (kIsWeb) return;

    if (AppPlatform.supportsClassicBluetooth && _classic != null) {
      await _classic!.cancelDiscovery();
    }

    await _bleScanSub?.cancel();
    _bleScanSub = null;

    if (fbp.FlutterBluePlus.isScanningNow) {
      await fbp.FlutterBluePlus.stopScan();
    }

    _stopScanUI();
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
      // 🛠️ PERF: Sort strictly on mutation, drastically saving UI thread CPU overhead.
      _discovered.sort((a, b) => (b.rssi ?? -100).compareTo(a.rssi ?? -100));
      _notify();
    }
  }

  // ── Connection ──────────────────────────────────────────

  Future<void> connectToDevice(BTDevice device) async {
    if (kIsWeb) return;
    if (_state == BtConnectionState.connecting) return;

    await stopDiscovery();
    await disconnect();

    _setState(BtConnectionState.connecting);
    _messages.clear();

    try {
      if (!device.isBLE &&
          AppPlatform.supportsClassicBluetooth &&
          _classic != null) {
        await _classic!.connect(
          address: device.address,
          onData: _onRawData,
          onDone: disconnect,
          onError: (e) => _setError('Classic link lost: $e'),
        );
      } else {
        _bleDevice = fbp.BluetoothDevice.fromId(device.address);
        await _bleDevice!.connect(timeout: const Duration(seconds: 15));

        if (AppPlatform.isAndroid) {
          // 🛠️ FIX: wrapped MTU request in a try-catch. Some Android devices
          // throw exceptions if MTU is negotiated automatically by the OS first.
          try {
            await _bleDevice!.requestMtu(512);
          } catch (e) {
            debugPrint('MTU request skipped/failed: $e');
          }
        }

        await _bleStateSub?.cancel();
        _bleStateSub = _bleDevice!.connectionState.listen((s) {
          if (s == fbp.BluetoothConnectionState.disconnected && isConnected) {
            disconnect();
          }
        });

        List<fbp.BluetoothService> services = [];
        int retry = 0;

        while (services.isEmpty && retry < 3) {
          services = await _bleDevice!.discoverServices();
          if (services.isEmpty) {
            await Future.delayed(const Duration(milliseconds: 600));
            retry++;
          }
        }

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

        if (rx == null || tx == null) {
          for (var s in services) {
            for (var c in s.characteristics) {
              if (rx == null &&
                  (c.properties.write || c.properties.writeWithoutResponse)) {
                rx = c;
              }
              if (tx == null && c.properties.notify) {
                tx = c;
              }
            }
          }
        }

        if (rx == null || tx == null) {
          throw Exception('Device does not support messaging.');
        }

        await tx.setNotifyValue(true);
        _bleNotifySub?.cancel(); // 🛠️ FIX: Memory leak protection
        _bleNotifySub = tx.onValueReceived.listen(_onRawData);
        _bleRx = rx;
      }

      _connectedDeviceName = device.name;
      _setState(BtConnectionState.connected);
    } catch (e) {
      await disconnect();
      _setError('Connection failed: $e');
    }
  }

  // ── Messaging ───────────────────────────────────────────

  void _onRawData(List<int> data) {
    _byteBuffer.addAll(data);
    bool hasNewMessages = false;

    int idx;
    // 🛠️ PERF: Removed `_byteBuffer.contains(10)`. Doing `contains` followed by `indexOf`
    // runs through the buffer O(N) twice. Just assigning and checking indexOf halves processing time.
    while ((idx = _byteBuffer.indexOf(10)) != -1) {
      try {
        final lineBytes = _byteBuffer.sublist(0, idx);
        final line = utf8.decode(lineBytes, allowMalformed: true).trim();

        if (line.isNotEmpty) {
          final msg = _parsePacket(line);
          if (msg != null) {
            _messages.add(msg);
            hasNewMessages = true;
          }
        }
      } catch (_) {
        // Ignored, bad sequence
      } finally {
        _byteBuffer.removeRange(0, idx + 1);
      }
    }

    // 🛠️ PERF: Batching state notifications. If a device bursts 10 lines at once,
    // it will now only trigger ONE UI rebuild, rather than 10 synchronous rebuilds.
    if (hasNewMessages) {
      _notify();
    }
  }

  Message? _parsePacket(String line) {
    try {
      final json = jsonDecode(line) as Map<String, dynamic>;
      final cipher = json['t'] as String? ?? '';
      final plain = _encryption.decrypt(cipher);

      return Message(
        id: _uuid.v4(),
        text: plain,
        encryptedText: cipher,
        isMine: false,
        timestamp: DateTime.now(),
      );
    } catch (_) {
      return Message(
        id: _uuid.v4(),
        text: 'Decryption Error: $line',
        encryptedText: line,
        isMine: false,
        timestamp: DateTime.now(),
        isDecryptionError: true,
      );
    }
  }

  Future<void> sendMessage(String text) async {
    if (kIsWeb) return;
    if (!isConnected || text.trim().isEmpty) return;

    final trimmed = text.trim();
    final encText = _encryption.encrypt(trimmed);
    final packet = utf8.encode('${jsonEncode({'t': encText})}\n');

    try {
      if (_classic != null && _classic!.isConnected) {
        await _classic!.send(Uint8List.fromList(packet));
      } else if (_bleRx != null) {
        int mtu = (_bleDevice?.mtuNow ?? 23) - 3;
        mtu = mtu.clamp(
            20, 512); // 🛠️ FIX: Clamped properly to prevent math out-of-bounds

        // 🛠️ FIX: Strictly check if the characteristic supports `writeWithoutResponse`
        bool withoutResponse = _bleRx!.properties.writeWithoutResponse;

        for (var i = 0; i < packet.length; i += mtu) {
          final end = (i + mtu < packet.length) ? i + mtu : packet.length;
          await _bleRx!
              .write(packet.sublist(i, end), withoutResponse: withoutResponse);
        }
      }

      _messages.add(Message(
        id: _uuid.v4(),
        text: trimmed,
        encryptedText: encText,
        isMine: true,
        timestamp: DateTime.now(),
      ));

      _notify();
    } catch (e) {
      _setError('Send failed: $e');
    }
  }

  // ── Public Methods ──────────────────────────────────────

  void updatePassphrase(String passphrase) {
    _encryption.updatePassphrase(passphrase);
    _notify();
  }

  void clearMessages() {
    _messages.clear();
    _notify();
  }

  // ── Lifecycle ───────────────────────────────────────────

  Future<void> disconnect() async {
    if (kIsWeb) return;

    await _bleNotifySub?.cancel();
    await _bleStateSub?.cancel();
    await _isScanningSub?.cancel(); // 🛠️ FIX: Added missing cleanup

    if (_bleDevice != null) {
      await _bleDevice!.disconnect();
    }

    if (_classic != null) {
      await _classic!.disconnect();
    }

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

  @override
  void dispose() {
    _disposed = true;
    _discoverySub?.cancel();
    _discoverySubject.close();
    _bleScanSub?.cancel();
    _bleNotifySub?.cancel();
    _bleStateSub?.cancel();
    _isScanningSub?.cancel(); // 🛠️ FIX: Added missing cleanup
    super.dispose();
  }
}
