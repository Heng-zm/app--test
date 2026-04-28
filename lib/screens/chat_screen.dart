import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../services/bluetooth_service.dart';
import '../services/wifi_service.dart';
import '../models/message_model.dart';
import '../theme/app_theme.dart';
import '../widgets/glow_container.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _showEncrypted = false;

  late BluetoothService _btService;
  late WifiService _wifiService;

  @override
  void initState() {
    super.initState();
    // 🟢 FIX: Bind listeners in initState instead of doing side-effects in build()
    _btService = context.read<BluetoothService>();
    _wifiService = context.read<WifiService>();

    _btService.addListener(_checkConnectionState);
    _wifiService.addListener(_checkConnectionState);
  }

  @override
  void dispose() {
    _btService.removeListener(_checkConnectionState);
    _wifiService.removeListener(_checkConnectionState);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // 🟢 FIX: Safe navigation handler that executes cleanly outside the build pipeline
  void _checkConnectionState() {
    if (!mounted) return;

    final bool isWide = MediaQuery.sizeOf(context).width >= 720;
    final bool isConnected = _btService.isConnected || _wifiService.isConnected;

    if (!isConnected && !isWide) {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isWide = MediaQuery.sizeOf(context).width >= 720;

    // 🟢 PERF: Flattened widget tree using context.watch
    final btService = context.watch<BluetoothService>();
    final wifiService = context.watch<WifiService>();

    final bool isConnected = btService.isConnected || wifiService.isConnected;

    // 🟢 PERF: Sort descending (newest first) to support reverse: true ListView
    final List<Message> allMessages = [
      ...btService.messages,
      ...wifiService.messages
    ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      appBar:
          _buildAppBar(context, btService, wifiService, isConnected, isWide),
      body: Column(
        children: [
          _SecurityStatusHeader(isWifi: wifiService.isConnected),
          Expanded(
            child: RepaintBoundary(
              child: allMessages.isEmpty
                  ? _buildEmptyState()
                  : _buildMessageList(allMessages),
            ),
          ),
          _buildInputArea(btService, wifiService, isConnected),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, BluetoothService bt,
      WifiService wifi, bool isConnected, bool isWide) {
    final String title = wifi.isConnected
        ? 'WLAN: ${wifi.localIP ?? 'Direct Link'}'
        : bt.connectedDeviceName ?? 'Secure Session';

    return AppBar(
      backgroundColor: AppTheme.bgDeep,
      elevation: 0,
      centerTitle: false,
      leading: isWide
          ? null
          : IconButton(
              icon: const Icon(Icons.arrow_back_ios_new,
                  color: AppTheme.accentCyan, size: 20),
              onPressed: () => Navigator.maybePop(context),
            ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary)),
          _ConnectionIndicator(
              isConnected: isConnected, isWifi: wifi.isConnected),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(
            _showEncrypted
                ? Icons.enhanced_encryption
                : Icons.no_encryption_gmailerrorred,
            color: _showEncrypted ? AppTheme.accentCyan : AppTheme.textDim,
            size: 20,
          ),
          onPressed: () => setState(() => _showEncrypted = !_showEncrypted),
        ),
        _buildPopupMenu(bt, wifi),
      ],
    );
  }

  Widget _buildMessageList(List<Message> messages) {
    return ListView.builder(
      // 🟢 PERF: Reversing the list eliminates the need for manual, janky scroll controllers.
      // The newest messages naturally push upward from the bottom, instantly adapting to the keyboard.
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      itemCount: messages.length,
      cacheExtent: 1500, // Keeps images slightly off-screen cached in memory
      itemBuilder: (context, index) {
        return _MessageBubble(
            key: ValueKey(messages[index].id),
            message: messages[index],
            showCipher: _showEncrypted);
      },
    );
  }

  Widget _buildInputArea(
      BluetoothService bt, WifiService wifi, bool isConnected) {
    // 🟢 FIX: Correctly check viewInsetsOf for keyboard height
    final double bottomPadding = MediaQuery.viewInsetsOf(context).bottom > 0
        ? 12.0
        : MediaQuery.paddingOf(context).bottom + 12.0;

    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, bottomPadding),
      decoration: const BoxDecoration(
        color: AppTheme.bgSurface,
        border: Border(top: BorderSide(color: AppTheme.borderGlow, width: 0.5)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.add_photo_alternate_outlined,
                color: isConnected ? AppTheme.accentCyan : AppTheme.textDim),
            onPressed: isConnected ? () => _pickAndSendImage(wifi) : null,
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              enabled: isConnected,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              textInputAction: TextInputAction.send,
              decoration: InputDecoration(
                hintText:
                    isConnected ? 'Type secure message...' : 'Radio Link Lost',
                hintStyle: const TextStyle(color: AppTheme.textDim),
                fillColor: AppTheme.bgDeep,
                filled: true,
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none),
              ),
              onSubmitted: (_) => _sendMessage(bt, wifi),
            ),
          ),
          const SizedBox(width: 8),
          GlowContainer(
            child: IconButton(
              onPressed: isConnected ? () => _sendMessage(bt, wifi) : null,
              icon: const Icon(Icons.send_rounded),
              style: IconButton.styleFrom(
                backgroundColor:
                    isConnected ? AppTheme.accentCyan : AppTheme.textDim,
                foregroundColor: AppTheme.bgDeep,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndSendImage(WifiService wifi) async {
    if (!wifi.isConnected) return;
    try {
      final XFile? xfile = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 35,
        maxWidth: 800,
      );
      if (xfile != null) {
        final bytes = await xfile.readAsBytes();
        await wifi.sendImage(bytes);
      }
    } catch (e) {
      debugPrint('Image Error: $e');
    }
  }

  void _sendMessage(BluetoothService bt, WifiService wifi) {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (wifi.isConnected) {
      wifi.sendMessage(text);
    } else if (bt.isConnected) {
      bt.sendMessage(text);
    }
    _controller.clear();
    _focusNode.requestFocus();
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.security,
              size: 48, color: AppTheme.accentCyan.withValues(alpha: 0.1)),
          const SizedBox(height: 12),
          const Text('Channel Secured',
              style: TextStyle(color: AppTheme.textDim, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildPopupMenu(BluetoothService bt, WifiService wifi) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary),
      onSelected: (val) {
        if (val == 'clear') {
          bt.clearMessages();
          wifi.clearMessages();
        }
        if (val == 'disconnect') {
          bt.disconnect();
          wifi.disconnect();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'clear', child: Text('Clear History')),
        const PopupMenuItem(
            value: 'disconnect',
            child:
                Text('Disconnect', style: TextStyle(color: AppTheme.danger))),
      ],
    );
  }
}

class _SecurityStatusHeader extends StatelessWidget {
  final bool isWifi;
  const _SecurityStatusHeader({required this.isWifi});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6),
      color: AppTheme.bgSurface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(isWifi ? Icons.wifi_lock : Icons.verified_user,
              color: AppTheme.accentGreen, size: 10),
          const SizedBox(width: 6),
          const Text('AES-256 ENCRYPTION ACTIVE',
              style: TextStyle(
                  color: AppTheme.textDim, fontSize: 8, letterSpacing: 1)),
        ],
      ),
    );
  }
}

class _ConnectionIndicator extends StatelessWidget {
  final bool isConnected;
  final bool isWifi;
  const _ConnectionIndicator({required this.isConnected, required this.isWifi});

  @override
  Widget build(BuildContext context) {
    final color = isConnected ? AppTheme.accentGreen : AppTheme.danger;
    return Row(
      children: [
        Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        const SizedBox(width: 6),
        Text(
          isConnected ? (isWifi ? 'WLAN SECURE' : 'BT SECURE') : 'OFFLINE',
          style:
              TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Message message;
  final bool showCipher;

  const _MessageBubble(
      {super.key, required this.message, required this.showCipher});

  @override
  Widget build(BuildContext context) {
    final bool isMe = message.isMine;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: () {
              if (!message.isImage) {
                Clipboard.setData(ClipboardData(text: message.text));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')));
              }
            },
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.75),
              padding: EdgeInsets.all(message.isImage ? 4 : 12),
              decoration: BoxDecoration(
                color: isMe
                    ? AppTheme.accentCyan.withValues(alpha: 0.12)
                    : AppTheme.bgCard,
                borderRadius: BorderRadius.circular(16).copyWith(
                  bottomRight: isMe ? const Radius.circular(2) : null,
                  bottomLeft: !isMe ? const Radius.circular(2) : null,
                ),
                border: Border.all(
                    color: isMe
                        ? AppTheme.accentCyan.withValues(alpha: 0.3)
                        : AppTheme.borderGlow),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.isImage)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        base64Decode(message.text),
                        fit: BoxFit.cover,
                        cacheWidth: 500,
                        // 🟢 FIX: Prevents images from flickering white when scrolled rapidly
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.broken_image,
                            color: AppTheme.danger),
                      ),
                    )
                  else
                    Text(message.text,
                        style: const TextStyle(
                            color: AppTheme.textPrimary, fontSize: 14)),
                  if (showCipher)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(message.encryptedText,
                          style: const TextStyle(
                              color: AppTheme.warning,
                              fontSize: 9,
                              fontFamily: 'monospace')),
                    ),
                ],
              ),
            ),
          ),
          Text(message.timeString,
              style: const TextStyle(color: AppTheme.textDim, fontSize: 9)),
        ],
      ),
    );
  }
}
