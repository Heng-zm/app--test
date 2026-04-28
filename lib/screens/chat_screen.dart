import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';

import '../services/bluetooth_service.dart';
import '../services/wifi_service.dart';
import '../models/message_model.dart';
import '../theme/app_theme.dart';
import '../widgets/glow_container.dart';

// ── Attachment types ──────────────────────────────────────────────────────────

enum _AttachKind { image, document }

class _PendingAttachment {
  final _AttachKind kind;
  final String name;
  final int sizeBytes;
  final Uint8List bytes;

  const _PendingAttachment({
    required this.kind,
    required this.name,
    required this.sizeBytes,
    required this.bytes,
  });

  bool get isImage => kind == _AttachKind.image;

  String get sizeLabel {
    if (sizeBytes < 1024) return '${sizeBytes}B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)}KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _showEncrypted = false;
  bool _isSending = false;

  // Pending attachment waiting for optional caption + user confirmation
  _PendingAttachment? _pendingAttachment;
  final TextEditingController _captionController = TextEditingController();

  late BluetoothService _btService;
  late WifiService _wifiService;

  // 🟢 PERF: Cached sorted message list — only recomputed when list sizes change.
  List<Message> _cachedMessages = [];
  int _lastBtCount = -1;
  int _lastWifiCount = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 🟢 FIX: Service lookup in didChangeDependencies, not initState.
    if (_lastBtCount == -1) {
      _btService = context.read<BluetoothService>();
      _wifiService = context.read<WifiService>();
      _btService.addListener(_onServiceChanged);
      _wifiService.addListener(_onServiceChanged);
    }
  }

  @override
  void dispose() {
    _btService.removeListener(_onServiceChanged);
    _wifiService.removeListener(_onServiceChanged);
    _controller.dispose();
    _captionController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (!mounted) return;

    final bool isWide = MediaQuery.sizeOf(context).width >= 720;
    final bool isConnected = _btService.isConnected || _wifiService.isConnected;

    if (!isConnected && !isWide) {
      // 🟢 FIX: Defer navigation to avoid calling Navigator mid-rebuild.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (Navigator.canPop(context)) Navigator.pop(context);
      });
      return;
    }

    _rebuildMessageCache();
  }

  void _rebuildMessageCache() {
    final btCount = _btService.messages.length;
    final wifiCount = _wifiService.messages.length;
    if (btCount == _lastBtCount && wifiCount == _lastWifiCount) return;

    _lastBtCount = btCount;
    _lastWifiCount = wifiCount;

    _cachedMessages = [
      ..._btService.messages,
      ..._wifiService.messages,
    ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bool isWide = MediaQuery.sizeOf(context).width >= 720;

    final btService = context.watch<BluetoothService>();
    final wifiService = context.watch<WifiService>();
    final bool isConnected = btService.isConnected || wifiService.isConnected;

    _rebuildMessageCache();

    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      appBar:
          _buildAppBar(context, btService, wifiService, isConnected, isWide),
      body: Column(
        children: [
          _SecurityStatusHeader(isWifi: wifiService.isConnected),
          Expanded(
            child: RepaintBoundary(
              child: _cachedMessages.isEmpty
                  ? _buildEmptyState()
                  : _buildMessageList(_cachedMessages),
            ),
          ),
          // Attachment preview sheet slides in above the input bar when a
          // file has been chosen but not yet sent.
          if (_pendingAttachment != null)
            _AttachmentPreviewBar(
              attachment: _pendingAttachment!,
              captionController: _captionController,
              onDismiss: _clearAttachment,
              onSend: () => _sendAttachment(wifiService),
              isSending: _isSending,
            ),
          _buildInputArea(btService, wifiService, isConnected),
        ],
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

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

  // ── Message list ──────────────────────────────────────────────────────────

  Widget _buildMessageList(List<Message> messages) {
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      itemCount: messages.length,
      cacheExtent: 1500,
      itemBuilder: (context, index) {
        return _MessageBubble(
          key: ValueKey(messages[index].id),
          message: messages[index],
          showCipher: _showEncrypted,
        );
      },
    );
  }

  // ── Input area ────────────────────────────────────────────────────────────

  Widget _buildInputArea(
      BluetoothService bt, WifiService wifi, bool isConnected) {
    // While an attachment is staged, the preview bar owns the caption input
    // and its own Send button, so collapse the main composer to just safe-area.
    if (_pendingAttachment != null) {
      return SizedBox(height: MediaQuery.paddingOf(context).bottom);
    }

    final double bottomPadding = MediaQuery.viewInsetsOf(context).bottom > 0
        ? 12.0
        : MediaQuery.paddingOf(context).bottom + 12.0;

    final bool canSend = isConnected && !_isSending;
    // Attachment only works over WiFi (WiFiService carries the binary payload).
    final bool canAttach = canSend && wifi.isConnected;

    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, bottomPadding),
      decoration: const BoxDecoration(
        color: AppTheme.bgSurface,
        border: Border(top: BorderSide(color: AppTheme.borderGlow, width: 0.5)),
      ),
      child: Row(
        children: [
          // ── Attachment button ────────────────────────────────────────
          IconButton(
            icon: Icon(Icons.attach_file_rounded,
                color: canAttach ? AppTheme.accentCyan : AppTheme.textDim),
            tooltip: 'Attach file or image',
            onPressed: canAttach ? () => _showAttachMenu(context, wifi) : null,
          ),
          // ── Text field ───────────────────────────────────────────────
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              enabled: canSend,
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
              onSubmitted: canSend ? (_) => _sendMessage(bt, wifi) : null,
            ),
          ),
          const SizedBox(width: 8),
          // ── Send button ──────────────────────────────────────────────
          GlowContainer(
            child: IconButton(
              onPressed: canSend ? () => _sendMessage(bt, wifi) : null,
              icon: const Icon(Icons.send_rounded),
              style: IconButton.styleFrom(
                backgroundColor:
                    canSend ? AppTheme.accentCyan : AppTheme.textDim,
                foregroundColor: AppTheme.bgDeep,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Attach menu ───────────────────────────────────────────────────────────

  void _showAttachMenu(BuildContext context, WifiService wifi) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AttachMenuSheet(
        onPickImage: () {
          Navigator.pop(context);
          _pickImage(wifi);
        },
        onPickDocument: () {
          Navigator.pop(context);
          _pickDocument(wifi);
        },
      ),
    );
  }

  // ── Pick image ────────────────────────────────────────────────────────────

  Future<void> _pickImage(WifiService wifi) async {
    if (!wifi.isConnected) return;
    try {
      final XFile? xfile = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 35,
        maxWidth: 800,
      );
      if (xfile == null) return;
      if (!mounted) return;

      final bytes = await xfile.readAsBytes();
      if (!mounted) return;

      setState(() {
        _pendingAttachment = _PendingAttachment(
          kind: _AttachKind.image,
          name: xfile.name,
          sizeBytes: bytes.length,
          bytes: bytes,
        );
        _captionController.clear();
      });
    } catch (e) {
      debugPrint('[Chat] Image pick error: $e');
    }
  }

  // ── Pick document ─────────────────────────────────────────────────────────

  Future<void> _pickDocument(WifiService wifi) async {
    if (!wifi.isConnected) return;
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      if (!mounted) return;

      final PlatformFile file = result.files.first;
      final Uint8List? bytes = file.bytes;
      if (bytes == null) return;

      setState(() {
        _pendingAttachment = _PendingAttachment(
          kind: _AttachKind.document,
          name: file.name,
          sizeBytes: bytes.length,
          bytes: bytes,
        );
        _captionController.clear();
      });
    } catch (e) {
      debugPrint('[Chat] Document pick error: $e');
    }
  }

  // ── Send attachment ───────────────────────────────────────────────────────

  Future<void> _sendAttachment(WifiService wifi) async {
    final attachment = _pendingAttachment;
    if (attachment == null || _isSending || !wifi.isConnected) return;

    setState(() => _isSending = true);

    try {
      final caption = _captionController.text.trim().isEmpty
          ? null
          : _captionController.text.trim();

      if (attachment.isImage) {
        await wifi.sendImage(attachment.bytes, caption: caption);
      } else {
        await wifi.sendDocument(
          attachment.bytes,
          fileName: attachment.name,
          caption: caption,
        );
      }

      if (mounted) _clearAttachment();
    } catch (e) {
      debugPrint('[Chat] Attachment send error: $e');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _clearAttachment() {
    setState(() {
      _pendingAttachment = null;
      _captionController.clear();
    });
    _focusNode.requestFocus();
  }

  // ── Text message ──────────────────────────────────────────────────────────

  Future<void> _sendMessage(BluetoothService bt, WifiService wifi) async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _controller.clear();
    _focusNode.requestFocus();

    try {
      if (wifi.isConnected) {
        await wifi.sendMessage(text);
      } else if (bt.isConnected) {
        await bt.sendMessage(text);
      }
    } catch (e) {
      debugPrint('[Chat] Send error: $e');
      if (mounted) _controller.text = text;
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  // ── Misc ──────────────────────────────────────────────────────────────────

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
          setState(() {
            _lastBtCount = -1;
            _lastWifiCount = -1;
            _cachedMessages = [];
          });
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

// ── Attach menu bottom sheet ──────────────────────────────────────────────────

class _AttachMenuSheet extends StatelessWidget {
  final VoidCallback onPickImage;
  final VoidCallback onPickDocument;

  const _AttachMenuSheet(
      {required this.onPickImage, required this.onPickDocument});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppTheme.textDim.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _AttachOption(
              icon: Icons.image_outlined,
              label: 'Send an image',
              sublabel: 'Choose from gallery',
              color: AppTheme.accentCyan,
              onTap: onPickImage,
            ),
            _AttachOption(
              icon: Icons.insert_drive_file_outlined,
              label: 'Send as a document',
              sublabel: 'Any file type',
              color: AppTheme.accentGreen,
              onTap: onPickDocument,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _AttachOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final Color color;
  final VoidCallback onTap;

  const _AttachOption({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(label,
          style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600)),
      subtitle: Text(sublabel,
          style: const TextStyle(color: AppTheme.textDim, fontSize: 11)),
    );
  }
}

// ── Attachment preview bar ────────────────────────────────────────────────────

/// Appears above the input bar once a file has been chosen.
/// Mirrors the Telegram "Send an image / Send as a file" UX:
/// thumbnail (or doc icon) + filename + size + caption field + Send.
class _AttachmentPreviewBar extends StatelessWidget {
  final _PendingAttachment attachment;
  final TextEditingController captionController;
  final VoidCallback onDismiss;
  final VoidCallback onSend;
  final bool isSending;

  const _AttachmentPreviewBar({
    required this.attachment,
    required this.captionController,
    required this.onDismiss,
    required this.onSend,
    required this.isSending,
  });

  @override
  Widget build(BuildContext context) {
    final double bottomPadding = MediaQuery.viewInsetsOf(context).bottom > 0
        ? 12.0
        : MediaQuery.paddingOf(context).bottom + 12.0;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        border: const Border(
            top: BorderSide(color: AppTheme.borderGlow, width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Preview row ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
            child: Row(
              children: [
                _buildLeading(),
                const SizedBox(width: 12),
                Expanded(child: _buildFileInfo()),
                IconButton(
                  icon: const Icon(Icons.close,
                      size: 18, color: AppTheme.textSecondary),
                  onPressed: onDismiss,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          // ── Caption + send ───────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, bottomPadding),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: captionController,
                    autofocus: true,
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Caption',
                      hintStyle: const TextStyle(color: AppTheme.textDim),
                      fillColor: AppTheme.bgDeep,
                      filled: true,
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: isSending ? null : (_) => onSend(),
                  ),
                ),
                const SizedBox(width: 8),
                GlowContainer(
                  child: IconButton(
                    onPressed: isSending ? null : onSend,
                    icon: isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppTheme.bgDeep))
                        : const Icon(Icons.send_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor:
                          isSending ? AppTheme.textDim : AppTheme.accentCyan,
                      foregroundColor: AppTheme.bgDeep,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeading() {
    if (attachment.isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          attachment.bytes,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.broken_image, color: AppTheme.danger, size: 40),
        ),
      );
    }
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.accentGreen.withValues(alpha: 0.12),
        border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.3)),
      ),
      child: const Icon(Icons.insert_drive_file_outlined,
          color: AppTheme.accentGreen, size: 24),
    );
  }

  Widget _buildFileInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          attachment.isImage ? 'Send an image' : 'Send as a file',
          style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          attachment.name,
          style: const TextStyle(color: AppTheme.textDim, fontSize: 11),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          attachment.sizeLabel,
          style: const TextStyle(color: AppTheme.textDim, fontSize: 10),
        ),
      ],
    );
  }
}

// ── Static widgets ────────────────────────────────────────────────────────────

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
              if (!message.isImage && !message.isDocument) {
                Clipboard.setData(ClipboardData(text: message.text));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')));
              }
            },
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.75),
              padding: EdgeInsets.all(
                  (message.isImage || message.isDocument) ? 4 : 12),
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
                    _ImageContent(message: message)
                  else if (message.isDocument)
                    _DocumentContent(message: message)
                  else
                    Text(message.text,
                        style: const TextStyle(
                            color: AppTheme.textPrimary, fontSize: 14)),
                  // Optional caption shown below image or document
                  if ((message.isImage || message.isDocument) &&
                      message.caption != null &&
                      message.caption!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                      child: Text(message.caption!,
                          style: const TextStyle(
                              color: AppTheme.textPrimary, fontSize: 13)),
                    ),
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

// ── Image bubble ──────────────────────────────────────────────────────────────

class _ImageContent extends StatelessWidget {
  final Message message;
  const _ImageContent({required this.message});

  @override
  Widget build(BuildContext context) {
    final bytes = message.imageBytes;
    if (bytes == null) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Icon(Icons.broken_image, color: AppTheme.danger),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.memory(
        bytes,
        fit: BoxFit.cover,
        cacheWidth: 500,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.broken_image, color: AppTheme.danger),
      ),
    );
  }
}

// ── Document bubble ───────────────────────────────────────────────────────────

class _DocumentContent extends StatelessWidget {
  final Message message;
  const _DocumentContent({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.accentGreen.withValues(alpha: 0.12),
              border: Border.all(
                  color: AppTheme.accentGreen.withValues(alpha: 0.3)),
            ),
            child: const Icon(Icons.insert_drive_file_outlined,
                color: AppTheme.accentGreen, size: 20),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.fileName ?? 'Document',
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (message.fileSizeLabel != null)
                  Text(message.fileSizeLabel!,
                      style: const TextStyle(
                          color: AppTheme.textDim, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
