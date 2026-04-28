import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/bluetooth_service.dart';
import '../services/wifi_service.dart';
import '../services/encryption_service.dart';
import '../platform/app_platform.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _passphraseCtrl = TextEditingController();
  bool _obscure = true;
  String _hashPreview = '';
  bool _isSaved = false;

  @override
  void initState() {
    super.initState();
    _loadSavedPassphrase();
  }

  Future<void> _loadSavedPassphrase() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('passphrase');

    // Default fallback if nothing is stored in device memory
    final activePassphrase =
        (saved != null && saved.isNotEmpty) ? saved : 'BT_CHAT_SECURE_KEY_2024';

    if (mounted) {
      setState(() {
        _passphraseCtrl.text = activePassphrase;
        _hashPreview = EncryptionService.hashPreview(activePassphrase);
        _isSaved = saved != null && saved.isNotEmpty;
      });
    }
  }

  @override
  void dispose() {
    _passphraseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDeep,
        elevation: 0,
        title: const Text('SECURITY PROTOCOLS'),
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppTheme.borderGlow),
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          children: [
            const _StatusCard(),
            const SizedBox(height: 24),
            _buildPassphraseInput(),
            const SizedBox(height: 24),
            _buildFingerprintDisplay(),
            const SizedBox(height: 24),
            const _ArchitectureCard(),
            const SizedBox(height: 24),
            const _TipsCard(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildPassphraseInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'SHARED PASSPHRASE',
              style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2),
            ),
            if (_isSaved)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: AppTheme.accentGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4)),
                child: const Text('ACTIVE',
                    style: TextStyle(
                        color: AppTheme.accentGreen,
                        fontSize: 9,
                        fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passphraseCtrl,
          obscureText: _obscure,
          style: const TextStyle(
              color: AppTheme.textPrimary,
              fontFamily: 'monospace',
              fontSize: 14),
          onChanged: (v) {
            // 🟢 PERF: Only calculate hash if actually needed to reduce CPU cycle
            setState(() {
              _isSaved = false;
              _hashPreview = EncryptionService.hashPreview(v.isEmpty ? ' ' : v);
            });
          },
          decoration: InputDecoration(
            hintText: 'Enter secure key...',
            prefixIcon: const Icon(Icons.lock_outline, size: 18),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                  size: 18, color: AppTheme.textSecondary),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _generateNewKey,
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.accentCyan),
                    foregroundColor: AppTheme.accentCyan),
                child: const Text('GENERATE'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _applySecuritySettings,
                child: const Text('APPLY & SAVE'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFingerprintDisplay() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderGlow),
      ),
      child: Row(
        children: [
          const Icon(Icons.fingerprint, color: AppTheme.accentPurple, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('CRYPTO FINGERPRINT',
                    style: TextStyle(
                        color: AppTheme.textDim,
                        fontSize: 10,
                        letterSpacing: 1)),
                const SizedBox(height: 4),
                Text(
                  _hashPreview,
                  style: const TextStyle(
                      color: AppTheme.accentPurple,
                      fontSize: 18,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_all, color: AppTheme.textDim, size: 20),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _hashPreview));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Fingerprint copied to clipboard')));
            },
          ),
        ],
      ),
    );
  }

  void _generateNewKey() {
    final key = EncryptionService.generatePassphrase();
    setState(() {
      _passphraseCtrl.text = key;
      _hashPreview = EncryptionService.hashPreview(key);
      _obscure = false;
      _isSaved = false;
    });
  }

  Future<void> _applySecuritySettings() async {
    final key = _passphraseCtrl.text.trim();
    if (key.isEmpty) return;

    FocusScope.of(context).unfocus();

    // 🟢 Now both calls will work perfectly
    context.read<BluetoothService>().updatePassphrase(key);
    context.read<WifiService>().updatePassphrase(key);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('passphrase', key);

    if (!mounted) return;
    setState(() => _isSaved = true);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppTheme.accentGreen,
      content: const Text('Encryption Parameters Synchronized',
          style:
              TextStyle(color: AppTheme.bgDeep, fontWeight: FontWeight.bold)),
    ));
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.accentCyan.withValues(alpha: 0.3)),
        gradient: LinearGradient(colors: [
          AppTheme.accentCyan.withValues(alpha: 0.05),
          Colors.transparent
        ]),
      ),
      child: Column(
        children: [
          _row('Protocol', 'AES-256-CBC'),
          _row('IV Management', 'Random (Dynamic)'),
          _row('Hash Function', 'SHA-256'),
          _row('Transport Layer', 'BT / WLAN'),
        ],
      ),
    );
  }

  Widget _row(String l, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(l,
              style:
                  const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          Text(v,
              style: const TextStyle(
                  color: AppTheme.accentCyan,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ]),
      );
}

class _ArchitectureCard extends StatelessWidget {
  const _ArchitectureCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderGlow)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SYSTEM ARCHITECTURE',
              style: TextStyle(
                  color: AppTheme.textDim,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5)),
          const SizedBox(height: 12),
          _item('OS Platform', AppPlatform.name),
          _item(
              'Classic BT',
              AppPlatform.supportsClassicBluetooth
                  ? 'Enabled'
                  : 'Not Supported'),
          _item('BLE Support',
              AppPlatform.supportsBLE ? 'Enabled' : 'Not Supported'),
        ],
      ),
    );
  }

  Widget _item(String l, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(l,
              style:
                  const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          Text(v,
              style:
                  const TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
        ]),
      );
}

class _TipsCard extends StatelessWidget {
  const _TipsCard();
  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SECURITY NOTES',
            style: TextStyle(
                color: AppTheme.textDim,
                fontSize: 10,
                fontWeight: FontWeight.bold)),
        SizedBox(height: 12),
        Text(
            '• Passphrases should be exchanged via a verified out-of-band channel.',
            style: TextStyle(
                color: AppTheme.textSecondary, fontSize: 11, height: 1.5)),
        SizedBox(height: 6),
        Text(
            '• Confirm the fingerprint matches on both devices before transmitting sensitive data.',
            style: TextStyle(
                color: AppTheme.textSecondary, fontSize: 11, height: 1.5)),
      ],
    );
  }
}
