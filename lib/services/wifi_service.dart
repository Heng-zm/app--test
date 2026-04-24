import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data'; // 🟢 NEW: Required for Uint8List (Image bytes)

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
  final List<int> _byteBuffer = [];

  bool _disposed = false;

  WifiService({required EncryptionService encryption})
      : _encryption = encryption;

  // ── Getters ─────────────────────────────────────────────
  WifiConnectionState get state => _state;
  List<Message> get messages => List.unmodifiable(_messages);
  bool get isConnected => _state == WifiConnectionState.connected;
  String? get errorMessage => _errorMessage;
  String? get localIP => _localIP;

  // ── Host (Server) Mode + Auto-Discovery Beacon ──────────
  Future<void> startHosting() async {
    if (kIsWeb) return;
    await disconnect();

    try {
      _setState(WifiConnectionState.hosting);

      final info = NetworkInfo();
      _localIP = await info.getWifiIP() ?? '192.168.43.1';

      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 4567);

      _serverSocket!.listen((Socket incomingSocket) {
        _socket = incomingSocket;

        _stopUdp();
        _serverSocket?.close();
        _serverSocket = null;

        _socketSub?.cancel();
        _socketSub = _socket!.listen(
          _onRawData,
          onError: (e) {
            _setError('Connection error: $e');
            disconnect();
          },
          onDone: disconnect,
        );

        _setState(WifiConnectionState.connected);
      });

      _startUdpBroadcast();
    } catch (e) {
      _setError('Failed to start host: $e');
    }
  }

  Future<void> _startUdpBroadcast() async {
    try {
      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
        reusePort: true,
      );
      _udpSocket!.broadcastEnabled = true;

      _broadcastTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
        if (_localIP != null && _udpSocket != null) {
          final data = utf8.encode('BTChatHost:$_localIP');
          _udpSocket!.send(data, InternetAddress('255.255.255.255'), 4568);
        }
      });
    } catch (e) {
      debugPrint('UDP Broadcast failed: $e');
    }
  }

  // ── Client Mode (Auto-Search) ───────────────────────────
  Future<void> startAutoConnect() async {
    if (kIsWeb) return;
    await disconnect();

    try {
      _setState(WifiConnectionState.searching);

      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        4568,
        reuseAddress: true,
        reusePort: true,
      );

      _udpSocket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read &&
            _state == WifiConnectionState.searching) {
          final datagram = _udpSocket!.receive();
          if (datagram != null) {
            final msg = utf8.decode(datagram.data);
            if (msg.startsWith('BTChatHost:')) {
              final ip = msg.substring(11).trim();
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

  // ── Client Mode (Manual IP Fallback) ────────────────────
  Future<void> connectToHost(String ipAddress) async {
    if (kIsWeb) return;
    if (_state != WifiConnectionState.searching) await disconnect();

    try {
      _setState(WifiConnectionState.connecting);

      _socket = await Socket.connect(ipAddress, 4567,
          timeout: const Duration(seconds: 5));

      _socketSub?.cancel();
      _socketSub = _socket!.listen(
        _onRawData,
        onError: (e) {
          _setError('Connection lost: $e');
          disconnect();
        },
        onDone: disconnect,
      );

      _setState(WifiConnectionState.connected);
    } catch (e) {
      _setError('Failed to connect: $e');
    }
  }

  // ── Data Processing ─────────────────────────────────────
  void _onRawData(List<int> data) {
    _byteBuffer.addAll(data);
    bool hasNewMessages = false;

    int idx;
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
      } finally {
        _byteBuffer.removeRange(0, idx + 1);
      }
    }

    if (hasNewMessages) _notify();
  }

  // 🟢 NEW: Parses JSON to detect if payload is 'text' or 'image'
  Message? _parsePacket(String line) {
    try {
      final json = jsonDecode(line) as Map<String, dynamic>;
      final cipher = json['t'] as String? ?? '';
      final type = json['type'] as String? ?? 'text'; // Check for image flag

      final plain = _encryption.decrypt(cipher);

      return Message(
        id: _uuid.v4(),
        text: plain,
        encryptedText: cipher,
        isMine: false,
        timestamp: DateTime.now(),
        isImage: type == 'image', // 🟢 Passes the flag to the UI
      );
    } catch (_) {
      return Message(
        id: _uuid.v4(),
        text: 'Decryption Error: Data Corrupted',
        encryptedText:
            line.substring(0, line.length > 50 ? 50 : line.length) + '...',
        isMine: false,
        timestamp: DateTime.now(),
        isDecryptionError: true,
      );
    }
  }

  // ── Send Message ────────────────────────────────────────
  Future<void> sendMessage(String text) async {
    if (_socket == null || !isConnected || text.trim().isEmpty) return;

    final trimmed = text.trim();
    final encText = _encryption.encrypt(trimmed);

    // 🟢 NEW: Explicitly mark this as a text packet
    final packet =
        utf8.encode('${jsonEncode({'type': 'text', 't': encText})}\n');

    try {
      _socket!.add(packet);
      await _socket!.flush();

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
      disconnect();
    }
  }

  // ── 🟢 NEW: Send Encrypted Image Method ─────────────────
  Future<void> sendImage(Uint8List imageBytes) async {
    if (_socket == null || !isConnected) return;

    // Convert raw image bytes to a base64 string, then encrypt it
    final base64String = base64Encode(imageBytes);
    final encText = _encryption.encrypt(base64String);

    // Explicitly mark this as an image packet
    final packet =
        utf8.encode('${jsonEncode({'type': 'image', 't': encText})}\n');

    try {
      _socket!.add(packet);
      await _socket!.flush();

      _messages.add(Message(
        id: _uuid.v4(),
        text: base64String, // Store base64 locally so the UI can render it
        encryptedText: 'Image Data Hidden (Cipher length: ${encText.length})',
        isMine: true,
        timestamp: DateTime.now(),
        isImage: true,
      ));

      _notify();
    } catch (e) {
      _setError('Image send failed: $e');
      disconnect();
    }
  }

  void clearMessages() {
    _messages.clear();
    _notify();
  }

  // ── Lifecycle & Cleanup ─────────────────────────────────
  void _stopUdp() {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    try {
      _udpSocket?.close();
    } catch (_) {}
    _udpSocket = null;
  }

  Future<void> disconnect() async {
    _stopUdp();
    await _socketSub?.cancel();
    _socketSub = null;

    try {
      await _socket?.close();
      _socket?.destroy();
    } catch (_) {}
    _socket = null;

    try {
      await _serverSocket?.close();
    } catch (_) {}
    _serverSocket = null;

    _byteBuffer.clear();
    _setState(WifiConnectionState.disconnected);
  }

  void _setState(WifiConnectionState s) {
    _state = s;
    _errorMessage = null;
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
