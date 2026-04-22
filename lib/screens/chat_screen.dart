import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/bluetooth_service.dart';
import '../models/message_model.dart';
import '../theme/app_theme.dart';
import '../widgets/glow_container.dart';
import 'home_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller   = TextEditingController();
  final _scrollCtrl   = ScrollController();
  final _focusNode    = FocusNode();
  bool  _showEncrypted = false;
  int   _prevCount     = 0;

  @override
  void initState() {
    super.initState();
    // Use post-frame callback to avoid calling setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = context.read<BluetoothService>();
    // Scroll whenever the message count grows
    if (service.messages.length != _prevCount) {
      _prevCount = service.messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BluetoothService>(
      builder: (context, service, _) {
        // Redirect to home if disconnected
        if (!service.isConnected &&
            service.state == BtConnectionState.disconnected) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.pushReplacement(context,
                  MaterialPageRoute(builder: (_) => const HomeScreen()));
            }
          });
        }

        // Auto-scroll on new messages
        if (service.messages.length != _prevCount) {
          _prevCount = service.messages.length;
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        }

        return Scaffold(
          backgroundColor: AppTheme.bgDeep,
          // resizeToAvoidBottomInset keeps chat above the keyboard
          resizeToAvoidBottomInset: true,
          appBar: _buildAppBar(context, service),
          body: Column(children: [
            _buildEncBadge(service),
            Expanded(child: _buildMessages(service)),
            _buildInputBar(service),
          ]),
        );
      },
    );
  }

  // ── AppBar ──────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(BuildContext ctx, BluetoothService svc) {
    return AppBar(
      backgroundColor: AppTheme.bgDeep,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: AppTheme.accentCyan, size: 17),
        onPressed: () async {
          await svc.disconnect();
          if (ctx.mounted) {
            Navigator.pushReplacement(ctx,
                MaterialPageRoute(builder: (_) => const HomeScreen()));
          }
        },
      ),
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(svc.connectedDeviceName ?? 'Device',
            style: const TextStyle(
                color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
        Row(children: [
          Container(width: 5, height: 5,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: AppTheme.accentGreen)),
          const SizedBox(width: 5),
          Text(
            svc.connectedDeviceAddress != null
                ? 'CONNECTED · ${_shortAddr(svc.connectedDeviceAddress!)}'
                : 'CONNECTED',
            style: const TextStyle(color: AppTheme.accentGreen, fontSize: 9,
                fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
        ]),
      ]),
      actions: [
        IconButton(
          icon: Icon(_showEncrypted ? Icons.lock_open : Icons.lock,
              color: _showEncrypted ? AppTheme.warning : AppTheme.textSecondary,
              size: 19),
          onPressed: () => setState(() => _showEncrypted = !_showEncrypted),
          tooltip: _showEncrypted ? 'Hide ciphertext' : 'Show ciphertext',
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary, size: 19),
          color: AppTheme.bgCard,
          onSelected: (v) async {
            if (v == 'clear') {
              svc.clearMessages();
            } else if (v == 'disconnect') {
              await svc.disconnect();
              if (ctx.mounted) {
                Navigator.pushReplacement(ctx,
                    MaterialPageRoute(builder: (_) => const HomeScreen()));
              }
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'clear',
                child: Row(children: [
                  Icon(Icons.delete_outline, color: AppTheme.textSecondary, size: 17),
                  SizedBox(width: 10),
                  Text('Clear messages', style: TextStyle(color: AppTheme.textPrimary)),
                ])),
            const PopupMenuItem(value: 'disconnect',
                child: Row(children: [
                  Icon(Icons.bluetooth_disabled, color: AppTheme.danger, size: 17),
                  SizedBox(width: 10),
                  Text('Disconnect', style: TextStyle(color: AppTheme.danger)),
                ])),
          ],
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppTheme.borderGlow),
      ),
    );
  }

  // ── Encryption badge ─────────────────────────────────────────────────────
  Widget _buildEncBadge(BluetoothService svc) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      color: AppTheme.bgSurface,
      child: Row(children: [
        const Icon(Icons.shield, color: AppTheme.accentGreen, size: 13),
        const SizedBox(width: 7),
        const Text('End-to-end encrypted · AES-256 · Random IV',
            style: TextStyle(color: AppTheme.accentGreen, fontSize: 10, fontWeight: FontWeight.w500)),
        const Spacer(),
        GestureDetector(
          onTap: () => setState(() => _showEncrypted = !_showEncrypted),
          child: Text(_showEncrypted ? 'HIDE CIPHER' : 'VIEW CIPHER',
              style: const TextStyle(color: AppTheme.accentCyan, fontSize: 9,
                  fontWeight: FontWeight.bold, letterSpacing: 1)),
        ),
      ]),
    );
  }

  // ── Message list ─────────────────────────────────────────────────────────
  Widget _buildMessages(BluetoothService svc) {
    if (svc.messages.isEmpty) return _buildEmptyState();

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      // Keep ListView from blocking input events when scrolling near the bottom
      physics: const ClampingScrollPhysics(),
      itemCount: svc.messages.length,
      itemBuilder: (_, i) {
        final msg  = svc.messages[i];
        final prev = i > 0 ? svc.messages[i - 1] : null;
        final showHeader = prev == null ||
            msg.timestamp.difference(prev.timestamp).inMinutes >= 5 ||
            msg.dateString != prev.dateString;
        return Column(children: [
          if (showHeader) _buildTimeDivider(msg),
          _buildBubble(msg),
        ]);
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle, color: AppTheme.bgCard,
          border: Border.all(color: AppTheme.borderGlow),
        ),
        child: const Icon(Icons.lock_outline, color: AppTheme.accentCyan, size: 32),
      ),
      const SizedBox(height: 16),
      const Text('SECURE CHANNEL OPEN',
          style: TextStyle(color: AppTheme.accentCyan, fontSize: 11,
              fontWeight: FontWeight.bold, letterSpacing: 2)),
      const SizedBox(height: 6),
      const Text('Messages are AES-256 encrypted before sending',
          style: TextStyle(color: AppTheme.textDim, fontSize: 11)),
    ]));
  }

  Widget _buildTimeDivider(Message msg) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        const Expanded(child: Divider(color: AppTheme.borderGlow, height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('${msg.dateString}  ${msg.timeString}',
              style: const TextStyle(color: AppTheme.textDim, fontSize: 9, letterSpacing: 1)),
        ),
        const Expanded(child: Divider(color: AppTheme.borderGlow, height: 1)),
      ]),
    );
  }

  Widget _buildBubble(Message msg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        mainAxisAlignment: msg.isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!msg.isMine) ...[
            _avatar(false),
            const SizedBox(width: 7),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: () => _copy(msg.text),
              child: Column(
                crossAxisAlignment:
                    msg.isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Container(
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.72),
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14).copyWith(
                        bottomRight: msg.isMine ? const Radius.circular(3) : null,
                        bottomLeft: !msg.isMine ? const Radius.circular(3) : null,
                      ),
                      gradient: msg.isMine
                          ? const LinearGradient(
                              colors: [Color(0xFF0A3D62), Color(0xFF0C2E4D)])
                          : null,
                      color: msg.isMine ? null : AppTheme.theirBubble,
                      border: Border.all(
                        color: msg.isMine
                            ? AppTheme.accentCyan.withOpacity(0.22)
                            : AppTheme.borderGlow,
                      ),
                      boxShadow: msg.isMine
                          ? [BoxShadow(color: AppTheme.accentCyan.withOpacity(0.08),
                              blurRadius: 8, offset: const Offset(0, 2))]
                          : null,
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (msg.isDecryptionError)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.warning_amber, color: AppTheme.warning, size: 13),
                          const SizedBox(width: 5),
                          Flexible(child: Text(msg.text,
                              style: const TextStyle(color: AppTheme.warning,
                                  fontSize: 13, fontStyle: FontStyle.italic))),
                        ])
                      else
                        Text(msg.text,
                            style: const TextStyle(color: AppTheme.textPrimary,
                                fontSize: 14, height: 1.4)),
                      if (_showEncrypted) ...[
                        const SizedBox(height: 5),
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: AppTheme.warning.withOpacity(0.3)),
                          ),
                          child: Text(
                            msg.encryptedText.length > 44
                                ? '${msg.encryptedText.substring(0, 44)}…'
                                : msg.encryptedText,
                            style: const TextStyle(color: AppTheme.warning,
                                fontSize: 8, fontFamily: 'monospace'),
                          ),
                        ),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 2),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.lock, size: 8, color: AppTheme.textDim),
                    const SizedBox(width: 3),
                    Text(msg.timeString,
                        style: const TextStyle(color: AppTheme.textDim, fontSize: 9)),
                  ]),
                ],
              ),
            ),
          ),
          if (msg.isMine) ...[
            const SizedBox(width: 7),
            _avatar(true),
          ],
        ],
      ),
    );
  }

  Widget _avatar(bool isMe) {
    return Container(
      width: 26, height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isMe ? AppTheme.accentCyan.withOpacity(0.12) : AppTheme.bgCard,
        border: Border.all(
            color: isMe ? AppTheme.accentCyan.withOpacity(0.3) : AppTheme.borderGlow),
      ),
      child: Icon(isMe ? Icons.person : Icons.bluetooth,
          size: 13, color: isMe ? AppTheme.accentCyan : AppTheme.textSecondary),
    );
  }

  // ── Input bar ────────────────────────────────────────────────────────────
  Widget _buildInputBar(BluetoothService svc) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, MediaQuery.of(context).viewInsets.bottom > 0 ? 8 : 18),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        border: const Border(top: BorderSide(color: AppTheme.borderGlow)),
      ),
      child: SafeArea(
        top: false,
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(svc),
              decoration: InputDecoration(
                hintText: 'Type encrypted message…',
                hintStyle: const TextStyle(color: AppTheme.textDim, fontSize: 13),
                prefixIcon: const Icon(Icons.lock_outline, color: AppTheme.textDim, size: 15),
                filled: true,
                fillColor: AppTheme.bgSurface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: const BorderSide(color: AppTheme.borderGlow)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: const BorderSide(color: AppTheme.borderGlow)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: const BorderSide(color: AppTheme.accentCyan, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              ),
            ),
          ),
          const SizedBox(width: 9),
          GlowContainer(
            child: GestureDetector(
              onTap: () => _send(svc),
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [AppTheme.accentCyan, AppTheme.accentTeal]),
                  boxShadow: [BoxShadow(
                      color: AppTheme.accentCyan.withOpacity(0.3), blurRadius: 10, spreadRadius: 1)],
                ),
                child: const Icon(Icons.send_rounded, color: AppTheme.bgDeep, size: 18),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Actions ──────────────────────────────────────────────────────────────
  void _send(BluetoothService svc) {
    if (_controller.text.trim().isEmpty) return;
    svc.sendMessage(_controller.text);
    _controller.clear();
    _focusNode.requestFocus();
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Copied to clipboard'),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppTheme.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      duration: const Duration(seconds: 1),
    ));
  }

  String _shortAddr(String addr) =>
      addr.length > 17 ? addr.substring(0, 8) : addr;
}
