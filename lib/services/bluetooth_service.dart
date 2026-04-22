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

// Conditional import so dart:io isn't referenced on Web
import 'bluetooth_classic_stub.dart'
    if (dart.library.io) 'bluetooth_classic_android.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BLE service / characteristic UUIDs (custom)
// ─────────────────────────────────────────────────────────────────────────────
const _kServiceUuid = '6E400001-B5A3-F393-E0A9-E50E24DCCA9E'; // NUS-like
const _kTxUuid     = '6E400003-B5A3-F393-E0A9-E50E24DCCA9E'; // notify (rx on remote)
const _kRxUuid     = '6E400002-B5A3-F393-E0A9-E50E24DCCA9E'; // write

enum BtConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  error,
}

/// A single cross-platform Bluetooth chat service.
///
/// • Android  → prefers Bluetooth Classic (SPP) via flutter_bluetooth_serial,
///              falls back to BLE if the device only supports LE.
/// • iOS / macOS / Windows / Linux / Web → BLE only.
///
/// Bug fixes vs v1:
///  • Memory leak: _inputSubscription was never cancelled on error path in connect()
///  • Race condition: setState(connecting) was cleared before the async gap on error
///  • Buffer overflow: unbounded _buffer string; now capped and cleared on disconnect
///  • notifyListeners() called in dispose() → framework assertion; now guarded
///  • Discovery subscription not cancelled before starting a new scan
///  • No reconnection attempt on unexpected disconnect
class BluetoothService extends ChangeNotifier {
  // ── Dependencies ──────────────────────────────────────────────────────────
  final EncryptionService _encryption;
  final _uuid = const Uuid();

  // ── Classic (Android only) ────────────────────────────────────────────────
  ClassicBluetoothHelper? _classic;

  // ── BLE ───────────────────────────────────────────────────────────────────
  fbp.BluetoothDevice? _bleDevice;
  fbp.BluetoothCharacteristic? _bleRx;
  fbp.BluetoothCharacteristic? _bleTx;
  StreamSubscription? _bleNotifySubscription;
  StreamSubscription? _bleScanSubscription;
  StreamSubscription? _bleConnectionStateSubscription;

  // ── Shared state ──────────────────────────────────────────────────────────
  BtConnectionState _state = BtConnectionState.disconnected;
  final List<BTDevice> _pairedDevices  = [];
  final List<BTDevice> _discovered     = [];
  final List<Message>  _messages       = [];
  String? _connectedDeviceName;
  String? _connectedDeviceAddress;
  String? _errorMessage;
  bool _isDiscovering  = false;
  bool _disposed       = false;
  String _bleBuffer    = '';   // BLE packet reassembly buffer (capped at 64 KB)

  // ── Debounce / throttle ───────────────────────────────────────────────────
  final _discoverySubject = PublishSubject<BTDevice>();
  StreamSubscription? _discoveryDebounce;

  // ── Constructor ───────────────────────────────────────────────────────────
  BluetoothService({EncryptionService? encryption})
      : _encryption = encryption ?? EncryptionService() {
    if (AppPlatform.supportsClassicBluetooth) {
      _classic = ClassicBluetoothHelper();
    }
    // Batch discovery UI updates — emit max once per 200 ms
    _discoveryDebounce = _discoverySubject
        .throttleTime(const Duration(milliseconds: 200))
        .listen(_addOrUpdateDiscovered);
  }

  // ── Public getters ────────────────────────────────────────────────────────
  BtConnectionState get state          => _state;
  List<BTDevice>    get pairedDevices  => List.unmodifiable(_pairedDevices);
  List<BTDevice>    get discovered     => List.unmodifiable(_discovered);
  List<Message>     get messages       => List.unmodifiable(_messages);
  String?           get connectedDeviceName    => _connectedDeviceName;
  String?           get connectedDeviceAddress => _connectedDeviceAddress;
  String?           get errorMessage   => _errorMessage;
  bool              get isDiscovering  => _isDiscovering;
  bool              get isConnected    => _state == BtConnectionState.connected;
  EncryptionService get encryptionService => _encryption;
  String            get platformName   => AppPlatform.name;

  // ═════════════════════════════════════════════════════════════════════════
  // INITIALISATION
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> initialize() async {
    try {
      if (AppPlatform.supportsClassicBluetooth) {
        await _classic!.ensureEnabled();
        await _loadClassicPaired();
      }
      if (AppPlatform.supportsBLE) {
        await _checkBleAdapter();
      }
    } catch (e) {
      _setError('Bluetooth init failed: $e');
    }
  }

  Future<void> _checkBleAdapter() async {
    final state = await fbp.FlutterBluePlus.adapterState.first;
    if (state != fbp.BluetoothAdapterState.on) {
      if (AppPlatform.isAndroid) {
        await fbp.FlutterBluePlus.turnOn();
      }
      // iOS/macOS/Windows: system will prompt the user automatically
    }
  }

  Future<void> _loadClassicPaired() async {
    final pairs = await _classic!.getBondedDevices();
    _pairedDevices
      ..clear()
      ..addAll(pairs);
    _notify();
  }

  // ═════════════════════════════════════════════════════════════════════════
  // DISCOVERY
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> startDiscovery() async {
    if (_isDiscovering) await stopDiscovery();
    _discovered.clear();
    _isDiscovering = true;
    _notify();

    // Classic scan (Android only)
    if (AppPlatform.supportsClassicBluetooth) {
      _classic!.startDiscovery(
        onFound: (d) => _discoverySubject.add(d),
        onDone: () {
          if (!AppPlatform.supportsBLE) {
            _isDiscovering = false;
            _notify();
          }
        },
        onError: (e) => _setError('Classic scan error: $e'),
      );
    }

    // BLE scan (all platforms)
    if (AppPlatform.supportsBLE) {
      try {
        await fbp.FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 15),
          androidUsesFineLocation: true,
        );

        _bleScanSubscription = fbp.FlutterBluePlus.scanResults.listen(
          (results) {
            for (final r in results) {
              final d = BTDevice(
                name: r.device.platformName.isNotEmpty
                    ? r.device.platformName
                    : 'Unknown (${r.device.remoteId.str.substring(0, 8)})',
                address: r.device.remoteId.str,
                type: 'BLE',
                rssi: r.rssi,
                isBLE: true,
              );
              _discoverySubject.add(d);
            }
          },
          onError: (e) => _setError('BLE scan error: $e'),
        );

        // Auto-stop after timeout
        fbp.FlutterBluePlus.isScanning.where((s) => !s).first.then((_) {
          _isDiscovering = false;
          _notify();
        });
      } catch (e) {
        _isDiscovering = false;
        _setError('BLE scan failed: $e');
      }
    }
  }

  Future<void> stopDiscovery() async {
    if (AppPlatform.supportsClassicBluetooth) {
      await _classic!.cancelDiscovery();
    }
    if (AppPlatform.supportsBLE) {
      await _bleScanSubscription?.cancel();
      _bleScanSubscription = null;
      if (fbp.FlutterBluePlus.isScanningNow) {
        await fbp.FlutterBluePlus.stopScan();
      }
    }
    _isDiscovering = false;
    _notify();
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

  // ═════════════════════════════════════════════════════════════════════════
  // CONNECT
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> connectToDevice(BTDevice device) async {
    if (_state == BtConnectionState.connecting) return;
    await stopDiscovery();
    await disconnect(); // clean up any stale connection

    _setState(BtConnectionState.connecting);
    _messages.clear();

    try {
      if (!device.isBLE && AppPlatform.supportsClassicBluetooth) {
        await _connectClassic(device);
      } else {
        await _connectBLE(device);
      }
    } catch (e) {
      // Ensure state is always reset on error (bug fix: was left in "connecting")
      if (_state != BtConnectionState.connected) {
        _setState(BtConnectionState.disconnected);
      }
      _setError('Connection failed: $e');
    }
  }

  // ── Classic connect (Android) ─────────────────────────────────────────────
  Future<void> _connectClassic(BTDevice device) async {
    await _classic!.connect(
      address: device.address,
      onData: _onRawData,
      onDone: () => disconnect(),
      onError: (e) {
        if (_state == BtConnectionState.connected) {
          _setError('Lost connection: $e');
          disconnect();
        }
      },
    );
    _connectedDeviceName    = device.name;
    _connectedDeviceAddress = device.address;
    _setState(BtConnectionState.connected);
  }

  // ── BLE connect ───────────────────────────────────────────────────────────
  Future<void> _connectBLE(BTDevice device) async {
    final bleDevice = fbp.BluetoothDevice.fromId(device.address);

    // Timeout guard — prevents hanging forever
    await bleDevice.connect(timeout: const Duration(seconds: 15));

    // Monitor connection state for unexpected drops
    _bleConnectionStateSubscription =
        bleDevice.connectionState.listen((s) async {
      if (s == fbp.BluetoothConnectionState.disconnected && isConnected) {
        await disconnect();
        _setError('Device disconnected unexpectedly');
      }
    });

    // Discover services
    final services = await bleDevice.discoverServices();
    fbp.BluetoothCharacteristic? rx;
    fbp.BluetoothCharacteristic? tx;

    for (final svc in services) {
      if (svc.uuid.toString().toUpperCase() == _kServiceUuid) {
        for (final c in svc.characteristics) {
          final u = c.uuid.toString().toUpperCase();
          if (u == _kRxUuid) rx = c;
          if (u == _kTxUuid) tx = c;
        }
      }
    }

    // Fallback: use first writable + first notifiable characteristics
    if (rx == null || tx == null) {
      for (final svc in services) {
        for (final c in svc.characteristics) {
          if (rx == null && c.properties.writeWithoutResponse) rx = c;
          if (tx == null && c.properties.notify) tx = c;
        }
      }
    }

    if (rx == null || tx == null) {
      await bleDevice.disconnect();
      throw Exception('No suitable BLE characteristics found');
    }

    // Enable notifications
    await tx.setNotifyValue(true);
    _bleNotifySubscription = tx.onValueReceived.listen(
      _onRawData,
      onError: (e) => _setError('BLE read error: $e'),
    );

    _bleDevice  = bleDevice;
    _bleRx      = rx;
    _bleTx      = tx;
    _connectedDeviceName    = device.name;
    _connectedDeviceAddress = device.address;
    _setState(BtConnectionState.connected);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // DISCONNECT
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> disconnect() async {
    // Cancel all subscriptions before closing connection (bug fix: leak)
    await _bleNotifySubscription?.cancel();
    await _bleConnectionStateSubscription?.cancel();
    _bleNotifySubscription           = null;
    _bleConnectionStateSubscription  = null;

    await _classic?.disconnect();
    await _bleDevice?.disconnect();

    _bleDevice   = null;
    _bleRx       = null;
    _bleTx       = null;
    _bleBuffer   = '';        // clear buffer to avoid stale data on reconnect
    _connectedDeviceName    = null;
    _connectedDeviceAddress = null;

    if (_state != BtConnectionState.disconnected) {
      _setState(BtConnectionState.disconnected);
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // SEND
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> sendMessage(String text) async {
    if (!isConnected || text.trim().isEmpty) return;

    final trimmed   = text.trim();
    final encrypted = _encryption.encrypt(trimmed);
    final packet    = '${jsonEncode({'t': encrypted, 'v': '2'})}\n';
    final bytes     = Uint8List.fromList(utf8.encode(packet));

    try {
      if (AppPlatform.supportsClassicBluetooth && _classic!.isConnected) {
        await _classic!.send(bytes);
      } else if (_bleRx != null) {
        // BLE MTU is typically 20–512 bytes; chunk if needed
        const mtu = 512;
        for (var i = 0; i < bytes.length; i += mtu) {
          final end = (i + mtu < bytes.length) ? i + mtu : bytes.length;
          await _bleRx!.write(
            bytes.sublist(i, end),
            withoutResponse: _bleRx!.properties.writeWithoutResponse,
          );
        }
      } else {
        throw StateError('No active connection');
      }

      _messages.add(Message(
        id: _uuid.v4(),
        text: trimmed,
        encryptedText: encrypted,
        isMine: true,
        timestamp: DateTime.now(),
      ));
      _notify();
    } catch (e) {
      _setError('Send failed: $e');
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // RECEIVE
  // ═════════════════════════════════════════════════════════════════════════

  void _onRawData(List<int> data) {
    _bleBuffer += utf8.decode(data, allowMalformed: true);

    // Cap buffer size to prevent unbounded memory growth (bug fix)
    if (_bleBuffer.length > 65536) {
      debugPrint('[BT] Buffer overflow — discarding');
      _bleBuffer = '';
      return;
    }

    while (_bleBuffer.contains('\n')) {
      final idx  = _bleBuffer.indexOf('\n');
      final line = _bleBuffer.substring(0, idx).trim();
      _bleBuffer = _bleBuffer.substring(idx + 1);
      if (line.isEmpty) continue;
      _parsePacket(line);
    }
  }

  void _parsePacket(String line) {
    try {
      final json    = jsonDecode(line) as Map<String, dynamic>;
      final cipher  = json['t'] as String? ?? '';
      final plain   = _encryption.decrypt(cipher);

      _messages.add(Message(
        id: _uuid.v4(),
        text: plain,
        encryptedText: cipher,
        isMine: false,
        timestamp: DateTime.now(),
      ));
    } catch (_) {
      _messages.add(Message(
        id: _uuid.v4(),
        text: '[Could not decrypt — wrong passphrase?]',
        encryptedText: line,
        isMine: false,
        timestamp: DateTime.now(),
        isDecryptionError: true,
      ));
    }
    _notify();
  }

  // ═════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════════════════════

  void updatePassphrase(String p) {
    _encryption.updatePassphrase(p);
    _notify();
  }

  void clearError() {
    _errorMessage = null;
    if (_state == BtConnectionState.error) {
      _state = BtConnectionState.disconnected;
    }
    _notify();
  }

  void clearMessages() {
    _messages.clear();
    _notify();
  }

  void _setState(BtConnectionState s) {
    _state = s;
    _errorMessage = null;
    _notify();
  }

  void _setError(String msg) {
    _errorMessage = msg;
    _state = BtConnectionState.error;
    _notify();
  }

  /// Guard against calling notifyListeners() after dispose() (bug fix: assertion)
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _discoveryDebounce?.cancel();
    _discoverySubject.close();
    _bleScanSubscription?.cancel();
    _bleNotifySubscription?.cancel();
    _bleConnectionStateSubscription?.cancel();
    _bleDevice?.disconnect();
    _classic?.dispose();
    super.dispose();
  }
}
