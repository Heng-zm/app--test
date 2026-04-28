import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../models/message_model.dart';
import 'encryption_service.dart';

enum WifiConnectionState {
  disconnected,
  hosting,
  searching,
  connecting,
  connected,
  error
}

class WifiService extends ChangeNotifier {
  final EncryptionService _encryption;
  final _uuid = const Uuid();

  ServerSocket? _serverSocket;
  Socket? _socket;
  StreamSubscription? _socketSub;

  RawDatagramSocket? _udpSocket;
  Timer? _broadcastTimer;

  WifiConnectionState _state = WifiConnectionState.disconnected;
  String? _errorMessage;
  String? _localIP;

  final List<Message> _messages = [];

  // 🟢 PERF: Use BytesBuilder for O(1) byte accumulation and efficient slicing
  final BytesBuilder _byteBuffer = BytesBuilder();

  bool _disposed = false;

  WifiService({required EncryptionService encryption})
      : _encryption = encryption;

  // ── Getters ─────────────────────────────────────────────
  WifiConnectionState get state => _state;
  List<Message> get messages => List.unmodifiable(_messages);
  bool get isConnected => _state == WifiConnectionState.connected;
  String? get errorMessage => _errorMessage;
  String? get localIP => _localIP;

  void clearMessages() {
    _messages.clear();
    _notify();
  }

  // ── Host Mode ───────────────────────────────────────────
  Future<void> startHosting() async {
    if (kIsWeb) return;
    await disconnect();

    try {
      _setState(WifiConnectionState.hosting);

      final info = NetworkInfo();
      _localIP = await info.getWifiIP();

      // Fallback if IP detection fails
      if (_localIP == null || _localIP == '0.0.0.0') {
        throw Exception('WiFi IP not detected. Connect to a network first.');
      }

      _serverSocket =
          await ServerSocket.bind(InternetAddress.anyIPv4, 4567, shared: true);

      _serverSocket!.listen((Socket incomingSocket) {
        _handleNewConnection(incomingSocket);
      });

      _startUdpBroadcast();
    } catch (e) {
      _setError('Host Error: $e');
    }
  }

  void _handleNewConnection(Socket incomingSocket) {
    _socket = incomingSocket;

    // 🟢 PERF: Disable Nagle's algorithm for real-time chat responsiveness
    _socket!.setOption(SocketOption.tcpNoDelay, true);

    _stopUdp();
    _serverSocket?.close();
    _serverSocket = null;

    _socketSub?.cancel();
    _socketSub = _socket!.listen(
      _onRawData,
      onError: (e) => disconnect(),
      onDone: () => disconnect(),
      cancelOnError: true,
    );

    _setState(WifiConnectionState.connected);
  }

  // ── Discovery Logic ─────────────────────────────────────
  Future<void> _startUdpBroadcast() async {
    try {
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0,
          reuseAddress: true);
      _udpSocket!.broadcastEnabled = true;

      // Calculate broadcast address (simple 255 fallback)
      String broadcastAddr = '255.255.255.255';
      if (_localIP != null && _localIP!.contains('.')) {
        broadcastAddr =
            '${_localIP!.substring(0, _localIP!.lastIndexOf('.'))}.255';
      }

      _broadcastTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
        if (_localIP != null && _udpSocket != null) {
          final data = utf8.encode('BTChatHost:$_localIP');
          try {
            _udpSocket!.send(data, InternetAddress(broadcastAddr), 4568);
          } catch (_) {}
        }
      });
    } catch (e) {
      debugPrint('UDP Discovery failed: $e');
    }
  }

  // ── Client Mode ─────────────────────────────────────────
  Future<void> startAutoConnect() async {
    if (kIsWeb) return;
    await disconnect();

    try {
      _setState(WifiConnectionState.searching);
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 4568,
          reuseAddress: true);

      _udpSocket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read &&
            _state == WifiConnectionState.searching) {
          final datagram = _udpSocket!.receive();
          if (datagram != null) {
            final msg = utf8.decode(datagram.data);
            if (msg.startsWith('BTChatHost:')) {
              final ip = msg.split(':')[1].trim();
              _stopUdp();
              connectToHost(ip);
            }
          }
        }
      });
    } catch (e) {
      _setError('Auto-search failed: $e');
    }
  }

  Future<void> connectToHost(String ipAddress) async {
    if (kIsWeb) return;
    if (_state != WifiConnectionState.searching) await disconnect();

    try {
      _setState(WifiConnectionState.connecting);
      _socket = await Socket.connect(ipAddress, 4567,
          timeout: const Duration(seconds: 5));
      _socket!.setOption(SocketOption.tcpNoDelay, true);

      _socketSub = _socket!.listen(
        _onRawData,
        onError: (e) => disconnect(),
        onDone: () => disconnect(),
        cancelOnError: true,
      );

      _setState(WifiConnectionState.connected);
    } catch (e) {
      _setError('Connection failed: $e');
    }
  }

  // ── Data Handling ───────────────────────────────────────
  void _onRawData(List<int> data) {
    if (_byteBuffer.length > 15 * 1024 * 1024)
      _byteBuffer.clear(); // Safety cap

    _byteBuffer.add(data);

    final Uint8List current = _byteBuffer.toBytes();
    int start = 0;

    while (true) {
      final int idx = current.indexOf(10, start); // Find Newline \n
      if (idx == -1) break;

      final packetBytes = current.sublist(start, idx);
      start = idx + 1;

      if (packetBytes.isEmpty) continue;

      final line = utf8.decode(packetBytes, allowMalformed: true);

      // 🟢 PERF: Use Isolates only for large payloads (>10KB)
      if (line.length > 10000) {
        _processPacketInBg(line);
      } else {
        _processPacketSync(line);
      }
    }

    // Clean up processed bytes
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

  /// Updates the encryption key for the Wi-Fi tunnel.
  void updatePassphrase(String passphrase) {
    _encryption.updatePassphrase(passphrase);
    _notify(); // Triggers rebuilds for any active chat sessions
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
    } catch (e) {
      debugPrint('Isolate processing error: $e');
    }
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

  // ── Send Logic ──────────────────────────────────────────
  Future<void> sendMessage(String text) async {
    final enc = _encryption.encrypt(text.trim());
    await _sendRawPacket({'type': 'text', 't': enc}, text.trim(), false);
  }

  Future<void> sendImage(Uint8List imageBytes) async {
    final base64String = base64Encode(imageBytes);
    final enc = _encryption.encrypt(base64String);
    await _sendRawPacket({'type': 'image', 't': enc}, base64String, true);
  }

  Future<void> _sendRawPacket(
      Map<String, String> data, String rawText, bool isImage) async {
    if (_socket == null || !isConnected) return;
    try {
      _socket!.add(utf8.encode('${jsonEncode(data)}\n'));
      await _socket!.flush();

      _messages.add(Message(
        id: _uuid.v4(),
        text: rawText,
        encryptedText: isImage ? 'Image Data' : data['t']!,
        isMine: true,
        timestamp: DateTime.now(),
        isImage: isImage,
      ));
      _notify();
    } catch (e) {
      _setError('Link failed');
      disconnect();
    }
  }

  // ── Lifecycle ───────────────────────────────────────────
  void _stopUdp() {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _udpSocket?.close();
    _udpSocket = null;
  }

  Future<void> disconnect() async {
    _stopUdp();
    await _socketSub?.cancel();
    _socketSub = null;

    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;

    try {
      await _serverSocket?.close();
    } catch (_) {}
    _serverSocket = null;

    _byteBuffer.clear();

    if (_state != WifiConnectionState.error) {
      _setState(WifiConnectionState.disconnected);
    }
  }

  void _setState(WifiConnectionState s) {
    _state = s;
    if (s != WifiConnectionState.error) _errorMessage = null;
    _notify();
  }

  void _setError(String m) {
    _errorMessage = m;
    _state = WifiConnectionState.error;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    disconnect();
    super.dispose();
  }
}
