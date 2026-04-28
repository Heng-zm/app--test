import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/wifi_service.dart';
import '../theme/app_theme.dart';

class WifiConnectionDialog extends StatefulWidget {
  const WifiConnectionDialog({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => const WifiConnectionDialog(),
    );
  }

  @override
  State<WifiConnectionDialog> createState() => _WifiConnectionDialogState();
}

class _WifiConnectionDialogState extends State<WifiConnectionDialog> {
  final _ipController = TextEditingController();
  final _focusNode = FocusNode();
  bool _showManualInput = false;

  @override
  void dispose() {
    _ipController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wifiService = context.watch<WifiService>();
    final size = MediaQuery.sizeOf(context);
    // 🟢 FIX: Handle keyboard pushing up the dialog
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardHeight),
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Container(
            constraints:
                BoxConstraints(maxWidth: 500, maxHeight: size.height * 0.8),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppTheme.accentCyan.withValues(alpha: 0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Divider(color: AppTheme.borderGlow, height: 1),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      // 🟢 PERF: ConstrainedBox prevents layout "jumps" during transitions
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 100),
                        child: _buildStateContent(wifiService),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.accentCyan.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.wifi_tethering,
              color: AppTheme.accentCyan, size: 22),
        ),
        const SizedBox(width: 12),
        const Text(
          'WLAN UPLINK',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        const Spacer(),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close, color: AppTheme.textDim, size: 20),
        ),
      ],
    );
  }

  Widget _buildStateContent(WifiService wifiService) {
    switch (wifiService.state) {
      case WifiConnectionState.connected:
        return _buildConnectedView(wifiService);
      case WifiConnectionState.hosting:
        return _buildHostingView(wifiService);
      case WifiConnectionState.searching:
      case WifiConnectionState.connecting:
        return _buildConnectingView(wifiService);
      case WifiConnectionState.disconnected:
      case WifiConnectionState.error:
        return _buildMenuView(wifiService);
    }
  }

  Widget _buildConnectedView(WifiService service) {
    return Column(
      key: const ValueKey('connected'),
      children: [
        const Icon(Icons.verified_user, color: AppTheme.accentGreen, size: 60),
        const SizedBox(height: 16),
        const Text('SECURE TUNNEL ACTIVE',
            style: TextStyle(
                color: AppTheme.accentGreen,
                fontWeight: FontWeight.bold,
                letterSpacing: 1)),
        const SizedBox(height: 32),
        _actionButton(
          label: 'TERMINATE UPLINK',
          icon: Icons.link_off,
          color: AppTheme.danger,
          onPressed: () {
            service.disconnect();
            Navigator.pop(context);
          },
        ),
      ],
    );
  }

  Widget _buildHostingView(WifiService service) {
    return Column(
      key: const ValueKey('hosting'),
      children: [
        const SizedBox(
          height: 40,
          width: 40,
          child: CircularProgressIndicator(
              color: AppTheme.accentCyan, strokeWidth: 2),
        ),
        const SizedBox(height: 24),
        const Text('BROADCASTING BEACON',
            style: TextStyle(
                color: AppTheme.textSecondary, fontSize: 11, letterSpacing: 2)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: AppTheme.bgDeep,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderGlow)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('GATEWAY IP',
                  style: TextStyle(color: AppTheme.textDim, fontSize: 9)),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(service.localIP ?? '0.0.0.0',
                      style: const TextStyle(
                          fontSize: 20,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accentCyan)),
                  IconButton(
                    icon: const Icon(Icons.copy,
                        color: AppTheme.accentCyan, size: 20),
                    onPressed: () {
                      if (service.localIP != null) {
                        Clipboard.setData(
                            ClipboardData(text: service.localIP!));
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('IP Copied')));
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _actionButton(
            label: 'STOP HOSTING',
            color: AppTheme.danger,
            onPressed: service.disconnect),
      ],
    );
  }

  Widget _buildConnectingView(WifiService service) {
    final isSearching = service.state == WifiConnectionState.searching;
    return Column(
      key: const ValueKey('searching'),
      children: [
        const SizedBox(
            height: 40,
            width: 40,
            child: CircularProgressIndicator(
                color: AppTheme.accentCyan, strokeWidth: 2)),
        const SizedBox(height: 24),
        Text(
            isSearching
                ? 'SCANNING FOR BEACON...'
                : 'ESTABLISHING HANDSHAKE...',
            style: const TextStyle(
                color: AppTheme.accentCyan,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1)),
        const SizedBox(height: 32),
        _actionButton(
            label: 'CANCEL',
            color: AppTheme.textDim,
            onPressed: service.disconnect),
      ],
    );
  }

  Widget _buildMenuView(WifiService service) {
    return Column(
      key: const ValueKey('menu'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInfoBox(),
        const SizedBox(height: 20),
        _actionButton(
            label: 'ACT AS HOST',
            icon: Icons.router,
            color: AppTheme.accentCyan,
            outlined: true,
            onPressed: service.startHosting),
        const SizedBox(height: 12),
        _actionButton(
            label: 'AUTO CONNECT',
            icon: Icons.radar,
            color: AppTheme.accentCyan,
            onPressed: service.startAutoConnect),
        Center(
          child: TextButton(
            onPressed: () {
              setState(() => _showManualInput = !_showManualInput);
              if (_showManualInput) {
                // 🟢 FIX: Auto-focus the input field when manual fallback is enabled
                Future.delayed(const Duration(milliseconds: 300),
                    () => _focusNode.requestFocus());
              }
            },
            child: Text(
                _showManualInput ? 'HIDE MANUAL INPUT' : 'MANUAL IP FALLBACK',
                style: const TextStyle(
                    color: AppTheme.textDim,
                    fontSize: 10,
                    decoration: TextDecoration.underline)),
          ),
        ),
        if (_showManualInput) ...[
          TextField(
            controller: _ipController,
            focusNode: _focusNode,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(
                color: Colors.white, fontFamily: 'monospace', fontSize: 14),
            decoration: InputDecoration(
              labelText: 'HOST GATEWAY IP',
              labelStyle:
                  const TextStyle(fontSize: 10, color: AppTheme.textDim),
              hintText: '192.168.x.x',
              filled: true,
              fillColor: AppTheme.bgDeep,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          _actionButton(
              label: 'LINK MANUALLY',
              color: AppTheme.textPrimary,
              onPressed: () {
                final ip = _ipController.text.trim();
                // 🟢 FIX: Basic IP Regex validation to prevent accidental handshake attempts on bad strings
                if (RegExp(r'^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$').hasMatch(ip)) {
                  service.connectToHost(ip);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Invalid IP format')));
                }
              }),
        ],
        if (service.errorMessage != null) _buildErrorBox(service.errorMessage!),
      ],
    );
  }

  Widget _buildInfoBox() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppTheme.bgSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderGlow)),
      child: const Text(
          '1. Enable Hotspot on Host\n2. Connect Client to that network\n3. Tap buttons below to sync',
          style: TextStyle(
              color: AppTheme.textSecondary, fontSize: 11, height: 1.5)),
    );
  }

  Widget _buildErrorBox(String msg) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: AppTheme.danger.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.danger.withValues(alpha: 0.2))),
      child: Text(msg,
          style: const TextStyle(color: AppTheme.danger, fontSize: 11),
          textAlign: TextAlign.center),
    );
  }

  Widget _actionButton(
      {required String label,
      required Color color,
      required VoidCallback onPressed,
      IconData? icon,
      bool outlined = false}) {
    return SizedBox(
      width: double.infinity,
      child: outlined
          ? OutlinedButton.icon(
              onPressed: onPressed,
              icon:
                  icon != null ? Icon(icon, size: 18) : const SizedBox.shrink(),
              label: Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12)),
              style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 14)))
          : ElevatedButton.icon(
              onPressed: onPressed,
              icon:
                  icon != null ? Icon(icon, size: 18) : const SizedBox.shrink(),
              label: Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: AppTheme.bgDeep,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0)),
    );
  }
}
