import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart'; // 🟢 NEW: Image Picker
import 'package:provider/provider.dart';

import '../services/bluetooth_service.dart';
import '../services/wifi_service.dart'; // 🟢 NEW: Wifi Service
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
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _focusNode = FocusNode();

  bool _showEncrypted = false;
  int _lastMsgCount = 0;

  @override
  void initState() {
    super.initState();
    _scrollToBottom(animated: false);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        if (animated) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        } else {
          _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isWide = MediaQuery.sizeOf(context).width >= 720;

    // 🟢 NEW: Listen to BOTH Bluetooth and Wi-Fi services
    return Consumer2<BluetoothService, WifiService>(
      builder: (context, btService, wifiService, _) {
        // Merge messages from both services and sort by time
        final List<Message> allMessages = [
          ...btService.messages,
          ...wifiService.messages
        ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));

        final bool isConnected =
            btService.isConnected || wifiService.isConnected;

        if (allMessages.length != _lastMsgCount) {
          _lastMsgCount = allMessages.length;
          _scrollToBottom();
        }

        if (!isConnected && !isWide) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          });
        }

        return Scaffold(
          backgroundColor: AppTheme.bgDeep,
          resizeToAvoidBottomInset: true,
          appBar: _buildAppBar(
              context, btService, wifiService, isConnected, isWide),
          body: Column(
            children: [
              _buildSecurityStatusHeader(wifiService.isConnected),
              Expanded(
                child: allMessages.isEmpty
                    ? _buildEmptyState()
                    : _buildMessageList(allMessages),
              ),
              _buildInputArea(btService, wifiService, isConnected),
            ],
          ),
        );
      },
    );
  }

  // ── AppBar ──────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(BuildContext context, BluetoothService bt,
      WifiService wifi, bool isConnected, bool isWide) {
    final title = wifi.isConnected
        ? 'WLAN: ${wifi.localIP ?? 'Connected'}'
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
          Text(
            title,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary),
          ),
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        isConnected ? AppTheme.accentGreen : AppTheme.danger),
              ),
              const SizedBox(width: 6),
              Text(
                isConnected
                    ? (wifi.isConnected ? 'WLAN ENCRYPTED' : 'BT ENCRYPTED')
                    : 'DISCONNECTED',
                style: TextStyle(
                    fontSize: 9,
                    color: isConnected ? AppTheme.accentGreen : AppTheme.danger,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2),
              ),
            ],
          ),
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
          tooltip: 'Toggle Ciphertext View',
        ),
        _buildPopupMenu(bt, wifi),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppTheme.borderGlow),
      ),
    );
  }

  Widget _buildPopupMenu(BluetoothService bt, WifiService wifi) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary),
      color: AppTheme.bgCard,
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
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'clear',
          child: Row(children: [
            Icon(Icons.delete_sweep_outlined,
                color: AppTheme.textSecondary, size: 18),
            SizedBox(width: 12),
            Text('Clear session logs',
                style: TextStyle(color: AppTheme.textPrimary)),
          ]),
        ),
        const PopupMenuItem(
          value: 'disconnect',
          child: Row(children: [
            Icon(Icons.link_off, color: AppTheme.danger, size: 18),
            SizedBox(width: 12),
            Text('Disconnect Link', style: TextStyle(color: AppTheme.danger)),
          ]),
        ),
      ],
    );
  }

  // ── Body Components ──────────────────────────────────────────────────────

  Widget _buildSecurityStatusHeader(bool isWifi) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: AppTheme.bgSurface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(isWifi ? Icons.wifi_tethering : Icons.verified_user,
              color: AppTheme.accentGreen, size: 12),
          const SizedBox(width: 8),
          const Text(
            'AES-256-CBC · SECURE CHANNEL ACTIVE',
            style: TextStyle(
                color: AppTheme.textDim,
                fontSize: 8,
                fontWeight: FontWeight.bold,
                letterSpacing: 1),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_person_outlined,
              size: 64, color: AppTheme.accentCyan.withValues(alpha: 0.05)),
          const SizedBox(height: 16),
          const Text(
            'Encryption synchronized.\nMessages are end-to-end encrypted.',
            textAlign: TextAlign.center,
            style:
                TextStyle(color: AppTheme.textDim, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(List<Message> messages) {
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(16),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        return _MessageBubble(
            message: messages[index], showCipher: _showEncrypted);
      },
    );
  }

  Widget _buildInputArea(
      BluetoothService bt, WifiService wifi, bool isConnected) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, MediaQuery.paddingOf(context).bottom + 12),
      decoration: const BoxDecoration(
        color: AppTheme.bgSurface,
        border: Border(top: BorderSide(color: AppTheme.borderGlow)),
      ),
      child: Row(
        children: [
          // 🟢 NEW: Image Attachment Button
          IconButton(
            icon: Icon(Icons.add_photo_alternate,
                color: isConnected ? AppTheme.accentCyan : AppTheme.textDim),
            onPressed: isConnected ? () => _pickAndSendImage(wifi) : null,
          ),

          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              enabled: isConnected,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(bt, wifi),
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText:
                    isConnected ? 'Type secure message...' : 'Radio Link Lost',
                hintStyle: const TextStyle(color: AppTheme.textDim),
                fillColor: AppTheme.bgDeep,
                filled: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GlowContainer(
            child: IconButton.filled(
              onPressed: isConnected ? () => _sendMessage(bt, wifi) : null,
              icon: const Icon(Icons.send_rounded, size: 20),
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

  // 🟢 NEW: Handles picking and sending images
  Future<void> _pickAndSendImage(WifiService wifi) async {
    if (!wifi.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('High-res images require WLAN/Hotspot connection.')),
      );
      return;
    }

    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 40, // Compress to save bandwidth
    );

    if (xfile != null) {
      final bytes = await xfile.readAsBytes();
      wifi.sendImage(bytes);
    }
  }

  void _sendMessage(BluetoothService bt, WifiService wifi) {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    // Send via Wi-Fi if connected, fallback to Bluetooth
    if (wifi.isConnected) {
      wifi.sendMessage(text);
    } else if (bt.isConnected) {
      bt.sendMessage(text);
    }

    _controller.clear();
    Future.microtask(() {
      if (mounted) _focusNode.requestFocus();
    });
  }
}

class _MessageBubble extends StatelessWidget {
  final Message message;
  final bool showCipher;

  const _MessageBubble({required this.message, required this.showCipher});

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMine;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: () {
              if (message.isImage) return; // Don't copy huge base64 strings
              Clipboard.setData(ClipboardData(text: message.text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Uplink Data Copied'),
                    duration: Duration(seconds: 1)),
              );
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 4, top: 8),
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.75),
              padding: EdgeInsets.all(
                  message.isImage ? 4 : 14), // Smaller padding for images
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
                crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  // ── DECRYPTION ERROR ──
                  if (message.isDecryptionError)
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: AppTheme.warning, size: 14),
                        SizedBox(width: 6),
                        Text('DECRYPTION FAILURE',
                            style: TextStyle(
                                color: AppTheme.warning,
                                fontSize: 12,
                                fontWeight: FontWeight.bold)),
                      ],
                    )

                  // ── 🟢 NEW: IMAGE RENDERER ──
                  else if (message.isImage)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.memory(
                        base64Decode(message.text),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          padding: const EdgeInsets.all(20),
                          color: AppTheme.bgDeep,
                          child: const Column(
                            children: [
                              Icon(Icons.broken_image,
                                  color: AppTheme.warning, size: 40),
                              SizedBox(height: 8),
                              Text('Corrupted Image Data',
                                  style: TextStyle(
                                      color: AppTheme.warning, fontSize: 10)),
                            ],
                          ),
                        ),
                      ),
                    )

                  // ── STANDARD TEXT ──
                  else
                    Text(message.text,
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 14,
                            height: 1.4)),

                  // ── CIPHERTEXT VIEW ──
                  if (showCipher) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppTheme.warning.withValues(alpha: 0.2))),
                      child: Text(
                        message.encryptedText,
                        style: const TextStyle(
                            color: AppTheme.warning,
                            fontSize: 9,
                            fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Metadata Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isMe)
                  const Icon(Icons.lock, size: 8, color: AppTheme.textDim),
                if (isMe) const SizedBox(width: 4),
                Text(message.timeString,
                    style:
                        const TextStyle(color: AppTheme.textDim, fontSize: 9)),
                if (!isMe) const SizedBox(width: 4),
                if (!isMe)
                  const Icon(Icons.lock, size: 8, color: AppTheme.textDim),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
