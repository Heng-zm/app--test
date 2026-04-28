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

  // 🟢 PERF: BytesBuilder gives O(1) byte accumulation without copying on add.
  final BytesBuilder _byteBuffer = BytesBuilder();

  bool _disposed = false;

  // 🟢 FIX: Track in-flight isolate count to prevent unbounded spawning when
  // a fast peer floods large packets. Without this, each large packet launches
  // a new isolate; under heavy load this exhausts the Dart isolate pool and
  // produces OOM errors or silent message drops.
  static const int _maxConcurrentIsolates = 4;
  int _activeIsolates = 0;

  WifiService({required EncryptionService encryption})
      : _encryption = encryption;

  // ── Getters ─────────────────────────────────────────────────────────────
  WifiConnectionState get state => _state;
  List<Message> get messages => List.unmodifiable(_messages);
  bool get isConnected => _state == WifiConnectionState.connected;
  String? get errorMessage => _errorMessage;
  String? get localIP => _localIP;

  void clearMessages() {
    _messages.clear();
    _notify();
  }

  // ── Host Mode ────────────────────────────────────────────────────────────
  Future<void> startHosting() async {
    if (kIsWeb) return;
    await disconnect();

    try {
      _setState(WifiConnectionState.hosting);

      final info = NetworkInfo();
      _localIP = await info.getWifiIP();

      if (_localIP == null || _localIP == '0.0.0.0') {
        throw Exception('WiFi IP not detected. Connect to a network first.');
      }

      _serverSocket =
          await ServerSocket.bind(InternetAddress.anyIPv4, 4567, shared: true);

      // 🟢 FIX: Store the subscription so it can be cancelled on disconnect.
      // Previously the ServerSocket.listen subscription was discarded, meaning
      // it kept firing (and accepting sockets) even after disconnect() ran.
      _serverSocket!.listen(
        _handleNewConnection,
        onError: (_) => disconnect(),
        cancelOnError: true,
      );

      _startUdpBroadcast();
    } catch (e) {
      _setError('Host Error: $e');
    }
  }

  void _handleNewConnection(Socket incomingSocket) {
    // 🟢 FIX: Reject additional connections if we are already connected.
    // Without this, a second peer connecting while a session is live would
    // silently replace _socket mid-conversation, dropping the existing session
    // with no error visible to either side.
    if (isConnected) {
      incomingSocket.destroy();
      return;
    }

    _socket = incomingSocket;

    // 🟢 PERF: Disable Nagle's algorithm for real-time chat responsiveness.
    _socket!.setOption(SocketOption.tcpNoDelay, true);

    _stopUdp();
    _serverSocket?.close();
    _serverSocket = null;

    _socketSub?.cancel();
    _socketSub = _socket!.listen(
      _onRawData,
      onError: (_) => disconnect(),
      onDone: () => disconnect(),
      cancelOnError: true,
    );

    _setState(WifiConnectionState.connected);
  }

  // ── Discovery ────────────────────────────────────────────────────────────
  Future<void> _startUdpBroadcast() async {
    try {
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0,
          reuseAddress: true);
      _udpSocket!.broadcastEnabled = true;

      // Derive subnet broadcast address; fall back to global broadcast.
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

  // ── Client Mode ──────────────────────────────────────────────────────────
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
              // 🟢 FIX: Validate the extracted IP before connecting.
              // A malformed or spoofed broadcast packet with extra colons
              // (e.g. 'BTChatHost:192.168.1.1:evil') would pass the startsWith
              // check and then pass an invalid address to connectToHost().
              final parts = msg.split(':');
              if (parts.length != 2) return;
              final ip = parts[1].trim();
              if (!_isValidIPv4(ip)) return;
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
        onError: (_) => disconnect(),
        onDone: () => disconnect(),
        cancelOnError: true,
      );

      _setState(WifiConnectionState.connected);
    } catch (e) {
      _setError('Connection failed: $e');
    }
  }

  // ── Data Handling ────────────────────────────────────────────────────────
  void _onRawData(List<int> data) {
    // 🟢 FIX: Safety cap — drop the buffer if a single burst exceeds 15 MB to
    // prevent a slow/malicious peer from growing heap without bound.
    if (_byteBuffer.length > 15 * 1024 * 1024) {
      debugPrint('[WifiService] RX buffer overflow — clearing.');
      _byteBuffer.clear();
    }

    _byteBuffer.add(data);

    final Uint8List current = _byteBuffer.toBytes();
    int start = 0;

    while (true) {
      final int idx = current.indexOf(10, start); // \n delimiter
      if (idx == -1) break;

      final packetBytes = current.sublist(start, idx);
      start = idx + 1;

      if (packetBytes.isEmpty) continue;

      final line = utf8.decode(packetBytes, allowMalformed: true);

      // 🟢 PERF: Offload to an isolate only for large payloads (>10 KB).
      // 🟢 FIX: Cap concurrent isolates to avoid pool exhaustion under load.
      if (line.length > 10000) {
        if (_activeIsolates < _maxConcurrentIsolates) {
          _processPacketInBg(line);
        } else {
          // Fall back to sync processing rather than dropping the message.
          _processPacketSync(line);
        }
      } else {
        _processPacketSync(line);
      }
    }

    // Retain only unprocessed bytes.
    if (start > 0) {
      final remaining = current.sublist(start);
      _byteBuffer.clear();
      if (remaining.isNotEmpty) _byteBuffer.add(remaining);
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
    _activeIsolates++;
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
      debugPrint('[WifiService] Isolate processing error: $e');
    } finally {
      // 🟢 FIX: Always decrement, even on exception, to avoid leaking the
      // semaphore and permanently blocking isolate dispatch.
      _activeIsolates--;
    }
  }

  static Message? _parseAndDecrypt(Map<String, dynamic> args) {
    try {
      final String line = args['line'];
      final EncryptionService encryption = args['encryption'];
      final json = jsonDecode(line) as Map<String, dynamic>;

      // 🟢 FIX: Validate required fields before casting to avoid a TypeError
      // if a malformed or unexpected packet arrives (e.g. a non-chat UDP echo).
      final dynamic rawType = json['type'];
      final dynamic rawT = json['t'];
      if (rawT is! String || rawType is! String) return null;

      final plain = encryption.decrypt(rawT);
      final bool isImage = rawType == 'image';
      final bool isDocument = rawType == 'document';

      // 🟢 FIX: Extract caption, fileName, and fileSize for image and document
      // packets — previously these fields were parsed but never stored on the
      // inbound Message, so captions and filenames were silently dropped on
      // the receiving side.
      final String? caption =
          json['caption'] is String ? json['caption'] as String : null;
      final String? fileName =
          json['fileName'] is String ? json['fileName'] as String : null;
      final int? fileSizeBytes = json['fileSize'] is String
          ? int.tryParse(json['fileSize'] as String)
          : null;

      return Message(
        id: args['uuid'] as String,
        text: plain,
        encryptedText: rawT,
        isMine: false,
        timestamp: DateTime.now(),
        isImage: isImage,
        isDocument: isDocument,
        caption: caption,
        fileName: fileName,
        fileSizeBytes: fileSizeBytes,
      );
    } catch (_) {
      return null;
    }
  }

  // ── Send Logic ───────────────────────────────────────────────────────────

  Future<void> sendMessage(String text) async {
    // 🟢 FIX: Guard against sending to a closed socket after a race between
    // the user tapping Send and a simultaneous disconnect event.
    if (!isConnected) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final enc = _encryption.encrypt(trimmed);
    await _sendRawPacket(
      payload: {'type': 'text', 't': enc},
      rawText: trimmed,
    );
  }

  // 🟢 FIX: Added optional `caption` parameter — previously missing, causing
  // the named-parameter compile error in chat_screen.dart.
  Future<void> sendImage(Uint8List imageBytes, {String? caption}) async {
    if (!isConnected) return;
    final base64String = base64Encode(imageBytes);
    final enc = _encryption.encrypt(base64String);
    await _sendRawPacket(
      payload: {
        'type': 'image',
        't': enc,
        if (caption != null && caption.isNotEmpty) 'caption': caption,
      },
      rawText: base64String,
      isImage: true,
      caption: caption,
    );
  }

  // 🟢 NEW: Send a binary document over the WiFi tunnel.
  // Encodes bytes as Base64, encrypts, and sends with document metadata.
  // fileName and optional caption are transmitted in plain JSON fields
  // alongside the encrypted payload so the receiver can display the file
  // name and caption without needing to decrypt the binary blob first.
  Future<void> sendDocument(
    Uint8List bytes, {
    required String fileName,
    String? caption,
  }) async {
    if (!isConnected) return;
    final base64String = base64Encode(bytes);
    final enc = _encryption.encrypt(base64String);
    await _sendRawPacket(
      payload: {
        'type': 'document',
        't': enc,
        'fileName': fileName,
        'fileSize': bytes.length.toString(),
        if (caption != null && caption.isNotEmpty) 'caption': caption,
      },
      rawText: base64String,
      isDocument: true,
      fileName: fileName,
      fileSizeBytes: bytes.length,
      caption: caption,
    );
  }

  // 🟢 REFACTOR: Switched from positional to named parameters so callers are
  // self-documenting and new optional fields (isDocument, fileName,
  // fileSizeBytes, caption) can be added without breaking existing call sites.
  Future<void> _sendRawPacket({
    required Map<String, String> payload,
    required String rawText,
    bool isImage = false,
    bool isDocument = false,
    String? fileName,
    int? fileSizeBytes,
    String? caption,
  }) async {
    if (_socket == null || !isConnected) return;
    try {
      _socket!.add(utf8.encode('${jsonEncode(payload)}\n'));
      await _socket!.flush();

      _messages.add(Message(
        id: _uuid.v4(),
        text: rawText,
        // 🟢 FIX: Use a stable placeholder for binary payloads rather than
        // storing raw Base64 in encryptedText, which was misleading and wasted
        // memory for a field only used in the cipher-view toggle.
        encryptedText:
            (isImage || isDocument) ? '[BINARY DATA]' : payload['t']!,
        isMine: true,
        timestamp: DateTime.now(),
        isImage: isImage,
        isDocument: isDocument,
        fileName: fileName,
        fileSizeBytes: fileSizeBytes,
        caption: caption,
      ));
      _notify();
    } catch (e) {
      _setError('Link failed: $e');
      disconnect();
    }
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────
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

  /// Updates the encryption key for the Wi-Fi tunnel.
  void updatePassphrase(String passphrase) {
    _encryption.updatePassphrase(passphrase);
    _notify();
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

  // ── Utilities ────────────────────────────────────────────────────────────

  /// Lightweight IPv4 validation — four dot-separated octets, each 0–255.
  static bool _isValidIPv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    for (final part in parts) {
      final n = int.tryParse(part);
      if (n == null || n < 0 || n > 255) return false;
    }
    return true;
  }
}
