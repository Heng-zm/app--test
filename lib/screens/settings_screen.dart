import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/bluetooth_service.dart';
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
  String _hashPreview =
      EncryptionService.hashPreview('BT_CHAT_SECURE_KEY_2024');
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _loadSavedPassphrase();
  }

  Future<void> _loadSavedPassphrase() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('passphrase');
    if (saved != null && saved.isNotEmpty && mounted) {
      setState(() {
        _passphraseCtrl.text = saved;
        _hashPreview = EncryptionService.hashPreview(saved);
        _saved = true;
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
        title: const Text('SECURITY SETTINGS'),
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppTheme.borderGlow),
        ),
      ),
      // Tap outside to dismiss keyboard
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _buildStatusCard(),
            const SizedBox(height: 22),
            _buildPassphraseSection(),
            const SizedBox(height: 22),
            _buildFingerprintCard(),
            const SizedBox(height: 22),
            _buildPlatformCard(),
            const SizedBox(height: 22),
            _buildTips(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ── Encryption Details ──────────────────────────────────────────────────

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.accentCyan.withOpacity(0.09),
            AppTheme.accentPurple.withOpacity(0.04)
          ],
        ),
        border: Border.all(color: AppTheme.accentCyan.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.shield_outlined,
                color: AppTheme.accentCyan, size: 20),
            const SizedBox(width: 10),
            const Text(
              'ENCRYPTION STATUS',
              style: TextStyle(
                color: AppTheme.accentCyan,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ]),
          const SizedBox(height: 14),
          _row('Algorithm', 'AES-256-CBC'),
          _row('Key derivation', 'SHA-256'),
          _row('IV generation', 'Random per message ✓'),
          _row('Version', 'v2 (Current)'),
          _row('Key fingerprint', _hashPreview,
              mono: true, color: AppTheme.accentGreen),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool mono = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Text(label,
              style:
                  const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: color ?? AppTheme.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontFamily: mono ? 'monospace' : null,
            ),
          ),
        ],
      ),
    );
  }

  // ── Passphrase Configuration ────────────────────────────────────────────

  Widget _buildPassphraseSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Text(
            'SHARED PASSPHRASE',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(width: 8),
          if (_saved)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.accentGreen.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'SAVED',
                style: TextStyle(
                    color: AppTheme.accentGreen,
                    fontSize: 8,
                    fontWeight: FontWeight.bold),
              ),
            ),
        ]),
        const SizedBox(height: 6),
        const Text(
          'Both devices must use the same exact passphrase to decrypt messages.',
          style: TextStyle(color: AppTheme.textDim, fontSize: 11),
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
            setState(() {
              _saved = false;
              _hashPreview =
                  v.isNotEmpty ? EncryptionService.hashPreview(v) : '00000000';
            });
          },
          decoration: InputDecoration(
            hintText: 'Enter shared passphrase…',
            prefixIcon:
                const Icon(Icons.key, color: AppTheme.textDim, size: 17),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                  color: AppTheme.textSecondary, size: 17),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _generatePassphrase,
                icon: const Icon(Icons.auto_awesome, size: 15),
                label: const Text('GENERATE'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.accentCyan,
                  side: const BorderSide(color: AppTheme.accentCyan),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _applyPassphrase,
                icon: const Icon(Icons.check, size: 15),
                label: const Text('APPLY & SAVE'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentCyan,
                  foregroundColor: AppTheme.bgDeep,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Visual Key Verification ─────────────────────────────────────────────

  Widget _buildFingerprintCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: AppTheme.bgCard,
        border: Border.all(color: AppTheme.borderGlow),
      ),
      child: Row(
        children: [
          const Icon(Icons.fingerprint, color: AppTheme.accentPurple, size: 22),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('KEY FINGERPRINT',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 9,
                      letterSpacing: 1.5)),
              Text(
                _hashPreview,
                style: const TextStyle(
                  color: AppTheme.accentPurple,
                  fontSize: 18,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                ),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _hashPreview));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Fingerprint Copied'),
                    duration: Duration(seconds: 1)),
              );
            },
            icon: const Icon(Icons.copy, color: AppTheme.textDim, size: 17),
          ),
        ],
      ),
    );
  }

  // ── Hardware Capabilities ───────────────────────────────────────────────

  Widget _buildPlatformCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: AppTheme.bgCard,
        border: Border.all(color: AppTheme.borderGlow),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'HARDWARE CAPABILITIES',
            style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 2),
          ),
          const SizedBox(height: 12),
          _capRow('OS Platform', AppPlatform.name),
          _capRow(
            'BT Classic (SPP)',
            AppPlatform.supportsClassicBluetooth
                ? '✓ Available'
                : '✗ Unsupported',
            color: AppPlatform.supportsClassicBluetooth
                ? AppTheme.accentGreen
                : AppTheme.textDim,
          ),
          _capRow(
            'BT Low Energy (BLE)',
            AppPlatform.supportsBLE ? '✓ Available' : '✗ Unsupported',
            color: AppPlatform.supportsBLE
                ? AppTheme.accentGreen
                : AppTheme.textDim,
          ),
          _capRow(
            'Permissions',
            AppPlatform.needsRuntimePermissions ? 'Managed' : 'System-level',
            color: AppTheme.textSecondary,
          ),
        ],
      ),
    );
  }

  Widget _capRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Text(label,
              style:
                  const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  color: color ?? AppTheme.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildTips() {
    const tips = [
      (
        '🔐',
        'Exchange passphrases via a secure, separate channel (e.g. in-person).'
      ),
      (
        '📋',
        'Visual check: The 8-digit fingerprint must be identical on both screens.'
      ),
      (
        '🔄',
        'If decryption fails, ensure both devices updated to the same passphrase.'
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SECURITY PROTOCOL',
          style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 2),
        ),
        const SizedBox(height: 12),
        ...tips.map((t) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.$1, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(t.$2,
                          style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11,
                              height: 1.4))),
                ],
              ),
            )),
      ],
    );
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  void _generatePassphrase() {
    final p = EncryptionService.generatePassphrase();
    _passphraseCtrl.text = p;
    setState(() {
      _hashPreview = EncryptionService.hashPreview(p);
      _obscure = false;
      _saved = false;
    });
  }

  Future<void> _applyPassphrase() async {
    final p = _passphraseCtrl.text.trim();
    if (p.isEmpty) return;

    FocusScope.of(context).unfocus();

    context.read<BluetoothService>().updatePassphrase(p);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('passphrase', p);

    if (!mounted) return;

    setState(() {
      _hashPreview = EncryptionService.hashPreview(p);
      _saved = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Passphrase Applied & Saved Locally'),
      backgroundColor: AppTheme.accentGreen.withOpacity(0.9),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }
}
