import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/wifi_service.dart';
import '../theme/app_theme.dart';

class WifiConnectionDialog extends StatefulWidget {
  const WifiConnectionDialog({super.key});

  /// Static helper to launch the dialog.
  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true, // Allow tapping outside to close
      builder: (_) => const WifiConnectionDialog(),
    );
  }

  @override
  State<WifiConnectionDialog> createState() => _WifiConnectionDialogState();
}

class _WifiConnectionDialogState extends State<WifiConnectionDialog> {
  final _ipController = TextEditingController();
  bool _showManualInput = false;

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 🛠️ PERF: Using select/watch specifically for the state to minimize rebuilds.
    final wifiService = context.watch<WifiService>();
    final size = MediaQuery.sizeOf(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      // 🛠️ FIX: Wrap in a GestureDetector to unfocus when tapping outside text fields
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
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Divider(color: AppTheme.borderGlow, height: 1),
              ),
              // 🛠️ FIX: Flexible + SingleChildScrollView prevents "Bottom Overflow"
              // when the manual IP keyboard is open.
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _buildStateContent(wifiService),
                  ),
                ),
              ),
            ],
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

  // ── Sub-Views ────────────────────────────────────────────────────────────

  Widget _buildConnectedView(WifiService service) {
    return Column(
      key: const ValueKey('connected'),
      children: [
        const Icon(Icons.verified_user, color: AppTheme.accentGreen, size: 60),
        const SizedBox(height: 16),
        const Text(
          'SECURE TUNNEL ACTIVE',
          style: TextStyle(
              color: AppTheme.accentGreen,
              fontWeight: FontWeight.bold,
              letterSpacing: 1),
        ),
        const SizedBox(height: 12),
        const Text(
          'Encrypted traffic is now routing over local hardware interface.',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: AppTheme.textSecondary, fontSize: 12, height: 1.5),
        ),
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
          height: 50,
          width: 50,
          child: CircularProgressIndicator(
              color: AppTheme.accentCyan, strokeWidth: 2),
        ),
        const SizedBox(height: 24),
        const Text('BROADCASTING BEACON',
            style: TextStyle(
                color: AppTheme.textSecondary, fontSize: 11, letterSpacing: 2)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
              color: AppTheme.bgDeep,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderGlow)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('GATEWAY IP',
                        style: TextStyle(color: AppTheme.textDim, fontSize: 9)),
                    const SizedBox(height: 4),
                    Text(service.localIP ?? '0.0.0.0',
                        style: const TextStyle(
                            fontSize: 18,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            color: AppTheme.accentCyan)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy,
                    color: AppTheme.accentCyan, size: 20),
                onPressed: () async {
                  if (service.localIP == null) return;
                  await Clipboard.setData(
                      ClipboardData(text: service.localIP!));
                  if (!mounted) return; // 🛠️ FIX: Async gap check
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('IP Copied to Clipboard'),
                      behavior: SnackBarBehavior.floating));
                },
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
          isSearching ? 'SCANNING FOR BEACON...' : 'ESTABLISHING HANDSHAKE...',
          style: const TextStyle(
              color: AppTheme.accentCyan,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1),
        ),
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
        const SizedBox(height: 24),
        _actionButton(
            label: 'ACT AS HOST (Phone A)',
            icon: Icons.router,
            color: AppTheme.accentCyan,
            outlined: true,
            onPressed: service.startHosting),
        const SizedBox(height: 16),
        _actionButton(
            label: 'AUTO CONNECT (Phone B)',
            icon: Icons.radar,
            color: AppTheme.accentCyan,
            onPressed: service.startAutoConnect),
        Center(
          child: TextButton(
            onPressed: () =>
                setState(() => _showManualInput = !_showManualInput),
            child: Text(
                _showManualInput ? 'HIDE MANUAL INPUT' : 'MANUAL IP FALLBACK',
                style: const TextStyle(
                    color: AppTheme.textDim,
                    fontSize: 10,
                    decoration: TextDecoration.underline)),
          ),
        ),
        if (_showManualInput) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _ipController,
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
                if (_ipController.text.isNotEmpty)
                  service.connectToHost(_ipController.text.trim());
              }),
        ],
        if (service.errorMessage != null) _buildErrorBox(service.errorMessage!),
      ],
    );
  }

  // ── UI Helpers ───────────────────────────────────────────────────────────

  Widget _buildInfoBox() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppTheme.bgSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderGlow)),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PROTOCOL INSTRUCTIONS',
              style: TextStyle(
                  color: AppTheme.accentCyan,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1)),
          SizedBox(height: 8),
          Text(
              '1. Enable Hotspot on Phone A\n2. Connect Phone B to that network\n3. Tap buttons below to sync',
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 11, height: 1.5)),
        ],
      ),
    );
  }

  Widget _buildErrorBox(String msg) {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: AppTheme.danger.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.danger.withValues(alpha: 0.2))),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppTheme.danger, size: 16),
          const SizedBox(width: 10),
          Expanded(
              child: Text(msg,
                  style:
                      const TextStyle(color: AppTheme.danger, fontSize: 11))),
        ],
      ),
    );
  }

  Widget _actionButton(
      {required String label,
      required Color color,
      required VoidCallback onPressed,
      IconData? icon,
      bool outlined = false}) {
    final style = outlined
        ? OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(vertical: 15))
        : ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: AppTheme.bgDeep,
            padding: const EdgeInsets.symmetric(vertical: 15),
            elevation: 0);

    return SizedBox(
      width: double.infinity,
      child: outlined
          ? OutlinedButton.icon(
              onPressed: onPressed,
              icon:
                  icon != null ? Icon(icon, size: 18) : const SizedBox.shrink(),
              label: Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1)))
          : ElevatedButton.icon(
              onPressed: onPressed,
              icon:
                  icon != null ? Icon(icon, size: 18) : const SizedBox.shrink(),
              label: Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1))),
    );
  }
}
