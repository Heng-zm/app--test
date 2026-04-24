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
    final wifiService = context.watch<WifiService>();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: AppTheme.accentCyan.withValues(alpha: 0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: AppTheme.accentCyan.withValues(alpha: 0.1),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── HEADER ──
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.accentCyan.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.wifi_tethering,
                      color: AppTheme.accentCyan, size: 24),
                ),
                const SizedBox(width: 16),
                const Text(
                  'WLAN UPLINK',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(height: 1, color: AppTheme.borderGlow),
            const SizedBox(height: 24),

            // ── DYNAMIC BODY ──
            Flexible(
              child: SingleChildScrollView(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _buildStateContent(wifiService),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStateContent(WifiService wifiService) {
    // ── CONNECTED STATE ──
    if (wifiService.state == WifiConnectionState.connected) {
      return Column(
        key: const ValueKey('connected'),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.accentGreen.withValues(alpha: 0.1),
            ),
            child:
                const Icon(Icons.shield, color: AppTheme.accentGreen, size: 48),
          ),
          const SizedBox(height: 20),
          const Text(
            'SECURE TUNNEL ESTABLISHED',
            style: TextStyle(
                color: AppTheme.accentGreen,
                fontWeight: FontWeight.bold,
                letterSpacing: 1),
          ),
          const SizedBox(height: 8),
          const Text(
            'Traffic is currently routing over high-speed local Wi-Fi.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.danger,
                side: BorderSide(color: AppTheme.danger.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () {
                wifiService.disconnect();
                Navigator.pop(context);
              },
              icon: const Icon(Icons.link_off),
              label: const Text('DISCONNECT'),
            ),
          ),
        ],
      );
    }

    // ── HOSTING STATE ──
    if (wifiService.state == WifiConnectionState.hosting) {
      return Column(
        key: const ValueKey('hosting'),
        children: [
          const CircularProgressIndicator(
              color: AppTheme.accentCyan, strokeWidth: 2),
          const SizedBox(height: 24),
          const Text(
            'BROADCASTING HOST BEACON',
            style: TextStyle(
                color: AppTheme.textPrimary, fontSize: 12, letterSpacing: 1.5),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.bgDeep,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderGlow),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('IP ADDRESS',
                        style:
                            TextStyle(color: AppTheme.textDim, fontSize: 10)),
                    const SizedBox(height: 4),
                    Text(
                      wifiService.localIP ?? 'Detecting...',
                      style: const TextStyle(
                        fontSize: 18,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        color: AppTheme.accentCyan,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.copy,
                      color: AppTheme.textSecondary, size: 20),
                  onPressed: () {
                    if (wifiService.localIP != null) {
                      Clipboard.setData(
                          ClipboardData(text: wifiService.localIP!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('IP Copied to Clipboard')),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          TextButton(
            onPressed: wifiService.disconnect,
            child: const Text('ABORT',
                style: TextStyle(color: AppTheme.danger, letterSpacing: 2)),
          ),
        ],
      );
    }

    // ── SEARCHING / CONNECTING STATE ──
    if (wifiService.state == WifiConnectionState.searching ||
        wifiService.state == WifiConnectionState.connecting) {
      final isSearching = wifiService.state == WifiConnectionState.searching;
      return Column(
        key: const ValueKey('searching'),
        children: [
          CircularProgressIndicator(
            color: isSearching ? AppTheme.accentCyan : AppTheme.accentGreen,
            strokeWidth: 2,
          ),
          const SizedBox(height: 24),
          Text(
            isSearching ? 'INTERCEPTING BEACON...' : 'NEGOTIATING HANDSHAKE...',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSearching ? AppTheme.accentCyan : AppTheme.accentGreen,
              letterSpacing: 2,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 32),
          TextButton(
            onPressed: wifiService.disconnect,
            child: const Text('ABORT',
                style: TextStyle(color: AppTheme.danger, letterSpacing: 2)),
          ),
        ],
      );
    }

    // ── DISCONNECTED STATE (MENU) ──
    return Column(
      key: const ValueKey('menu'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Instructions
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.bgSurface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('1. Turn on Mobile Hotspot on Phone A',
                  style:
                      TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              SizedBox(height: 6),
              Text('2. Connect Phone B to that Hotspot',
                  style:
                      TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Host Button
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.accentCyan,
            side: BorderSide(color: AppTheme.accentCyan.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: const Icon(Icons.router),
          label: const Text('ACT AS HOST (Phone A)'),
          onPressed: wifiService.startHosting,
        ),

        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(
              child: Text('OR',
                  style: TextStyle(
                      color: AppTheme.textDim,
                      fontSize: 12,
                      fontWeight: FontWeight.bold))),
        ),

        // Auto Connect Button
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accentCyan,
            foregroundColor: AppTheme.bgDeep,
            padding: const EdgeInsets.symmetric(vertical: 14),
            elevation: 0,
          ),
          icon: const Icon(Icons.radar),
          label: const Text('AUTO CONNECT (Phone B)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          onPressed: wifiService.startAutoConnect,
        ),

        const SizedBox(height: 8),

        // Manual IP Expander (Fallback)
        Center(
          child: TextButton(
            onPressed: () =>
                setState(() => _showManualInput = !_showManualInput),
            child: Text(
              _showManualInput ? 'Hide Manual IP' : 'Manual IP Fallback',
              style: const TextStyle(
                  color: AppTheme.textDim,
                  fontSize: 11,
                  decoration: TextDecoration.underline),
            ),
          ),
        ),

        if (_showManualInput) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _ipController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(
                color: AppTheme.textPrimary, fontFamily: 'monospace'),
            decoration: InputDecoration(
              labelText: 'Host IP Address',
              hintText: '192.168.43.1',
              labelStyle: const TextStyle(color: AppTheme.textDim),
              hintStyle:
                  TextStyle(color: AppTheme.textDim.withValues(alpha: 0.5)),
              filled: true,
              fillColor: AppTheme.bgSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.accentCyan),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.bgSurface,
              foregroundColor: AppTheme.textPrimary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () {
              if (_ipController.text.isNotEmpty) {
                wifiService.connectToHost(_ipController.text.trim());
              }
            },
            child: const Text('CONNECT MANUALLY'),
          ),
        ],

        // Error Message
        if (wifiService.errorMessage != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline,
                    color: AppTheme.danger, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    wifiService.errorMessage!,
                    style:
                        const TextStyle(color: AppTheme.danger, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ]
      ],
    );
  }
}
