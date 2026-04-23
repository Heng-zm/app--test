import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/bluetooth_service.dart';
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
    // Initialize view at the bottom
    _scrollToBottom(animated: false);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Handles smooth scrolling to the bottom of the message list
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
    // Standard Tablet/Desktop breakpoint
    final bool isWide = MediaQuery.of(context).size.width >= 720;

    return Consumer<BluetoothService>(
      builder: (context, service, _) {
        // 1. Auto-scroll logic: Trigger whenever the message list updates
        if (service.messages.length != _lastMsgCount) {
          _lastMsgCount = service.messages.length;
          _scrollToBottom();
        }

        // 2. Lifecycle logic: On mobile, pop back to home if connection is lost
        if (!service.isConnected && !isWide) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          });
        }

        return Scaffold(
          backgroundColor: AppTheme.bgDeep,
          resizeToAvoidBottomInset: true,
          appBar: _buildAppBar(context, service, isWide),
          body: Column(
            children: [
              _buildSecurityStatusHeader(),
              Expanded(
                child: service.messages.isEmpty
                    ? _buildEmptyState()
                    : _buildMessageList(service.messages),
              ),
              _buildInputArea(service),
            ],
          ),
        );
      },
    );
  }

  // ── AppBar ──────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(
      BuildContext context, BluetoothService service, bool isWide) {
    return AppBar(
      backgroundColor: AppTheme.bgDeep,
      elevation: 0,
      centerTitle: false,
      // On wide screens (tablets), hide the back button as the chat is a side-panel
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
            service.connectedDeviceName ?? 'Secure Session',
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
                    color: service.isConnected
                        ? AppTheme.accentGreen
                        : AppTheme.danger),
              ),
              const SizedBox(width: 6),
              Text(
                service.isConnected ? 'ENCRYPTED' : 'DISCONNECTED',
                style: TextStyle(
                    fontSize: 9,
                    color: service.isConnected
                        ? AppTheme.accentGreen
                        : AppTheme.danger,
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
        _buildPopupMenu(service),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppTheme.borderGlow),
      ),
    );
  }

  Widget _buildPopupMenu(BluetoothService service) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary),
      color: AppTheme.bgCard,
      onSelected: (val) {
        if (val == 'clear') {
          service.clearMessages();
        }
        if (val == 'disconnect') {
          service.disconnect();
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

  Widget _buildSecurityStatusHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: AppTheme.bgSurface,
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.verified_user, color: AppTheme.accentGreen, size: 12),
          SizedBox(width: 8),
          Text(
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
              size: 64, color: AppTheme.accentCyan.withOpacity(0.05)),
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
        final msg = messages[index];
        return _MessageBubble(message: msg, showCipher: _showEncrypted);
      },
    );
  }

  Widget _buildInputArea(BluetoothService service) {
    final bool canChat = service.isConnected;

    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 8, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        border: const Border(top: BorderSide(color: AppTheme.borderGlow)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              enabled: canChat,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(service),
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText:
                    canChat ? 'Type secure message...' : 'Radio Link Lost',
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
          const SizedBox(width: 12),
          GlowContainer(
            child: IconButton.filled(
              onPressed: canChat ? () => _sendMessage(service) : null,
              icon: const Icon(Icons.send_rounded, size: 20),
              // Fixed Material 3 styling
              style: IconButton.styleFrom(
                backgroundColor:
                    canChat ? AppTheme.accentCyan : AppTheme.textDim,
                foregroundColor: AppTheme.bgDeep,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _sendMessage(BluetoothService service) {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }
    service.sendMessage(text);
    _controller.clear();
    // Retain focus for quick replying
    _focusNode.requestFocus();
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
                  maxWidth: MediaQuery.of(context).size.width * 0.75),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe
                    ? AppTheme.accentCyan.withOpacity(0.12)
                    : AppTheme.bgCard,
                borderRadius: BorderRadius.circular(16).copyWith(
                  bottomRight: isMe ? const Radius.circular(2) : null,
                  bottomLeft: !isMe ? const Radius.circular(2) : null,
                ),
                border: Border.all(
                    color: isMe
                        ? AppTheme.accentCyan.withOpacity(0.3)
                        : AppTheme.borderGlow),
              ),
              child: Column(
                crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  // Decryption Error Logic
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
                                fontWeight: FontWeight.bold,
                                fontStyle: FontStyle.italic)),
                      ],
                    )
                  else
                    Text(
                      message.text,
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                          height: 1.4),
                    ),

                  // Toggleable Ciphertext View
                  if (showCipher) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppTheme.warning.withOpacity(0.2))),
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
                Text(
                  message.timeString,
                  style: const TextStyle(color: AppTheme.textDim, fontSize: 9),
                ),
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
