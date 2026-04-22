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
  bool  _obscure = true;
  String _hashPreview = EncryptionService.hashPreview('BT_CHAT_SECURE_KEY_2024');
  bool  _saved = false;

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
        title: const Text('SECURITY SETTINGS'),
        bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: AppTheme.borderGlow)),
      ),
      body: ListView(
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
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [AppTheme.accentCyan.withOpacity(0.09), AppTheme.accentPurple.withOpacity(0.04)],
        ),
        border: Border.all(color: AppTheme.accentCyan.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.shield_outlined, color: AppTheme.accentCyan, size: 20),
          const SizedBox(width: 10),
          const Text('ENCRYPTION STATUS',
              style: TextStyle(color: AppTheme.accentCyan, fontSize: 12,
                  fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        ]),
        const SizedBox(height: 14),
        _row('Algorithm', 'AES-256-CBC'),
        _row('Key derivation', 'SHA-256'),
        _row('IV generation', 'Random per message ✓'),
        _row('Version', 'v2 (with legacy fallback)'),
        _row('Key fingerprint', _hashPreview, mono: true, color: AppTheme.accentGreen),
      ]),
    );
  }

  Widget _row(String label, String value, {bool mono = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(children: [
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        const Spacer(),
        Text(value, style: TextStyle(
          color: color ?? AppTheme.textPrimary,
          fontSize: 12, fontWeight: FontWeight.w600,
          fontFamily: mono ? 'monospace' : null,
        )),
      ]),
    );
  }

  Widget _buildPassphraseSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('SHARED PASSPHRASE',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 10,
                fontWeight: FontWeight.bold, letterSpacing: 2)),
        const SizedBox(width: 8),
        if (_saved)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.accentGreen.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('SAVED',
                style: TextStyle(color: AppTheme.accentGreen, fontSize: 9,
                    fontWeight: FontWeight.bold)),
          ),
      ]),
      const SizedBox(height: 5),
      const Text('Both devices must use the same passphrase.',
          style: TextStyle(color: AppTheme.textDim, fontSize: 12)),
      const SizedBox(height: 12),
      TextField(
        controller: _passphraseCtrl,
        obscureText: _obscure,
        style: const TextStyle(color: AppTheme.textPrimary,
            fontFamily: 'monospace', fontSize: 14),
        onChanged: (v) {
          if (v.isNotEmpty) setState(() => _hashPreview = EncryptionService.hashPreview(v));
        },
        decoration: InputDecoration(
          hintText: 'Enter shared passphrase…',
          prefixIcon: const Icon(Icons.key, color: AppTheme.textDim, size: 17),
          suffixIcon: IconButton(
            icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                color: AppTheme.textSecondary, size: 17),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Row(children: [
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
          ),
        ),
      ]),
    ]);
  }

  Widget _buildFingerprintCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: AppTheme.bgCard,
        border: Border.all(color: AppTheme.borderGlow),
      ),
      child: Row(children: [
        const Icon(Icons.fingerprint, color: AppTheme.accentPurple, size: 22),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('KEY FINGERPRINT',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 9, letterSpacing: 1.5)),
          Text(_hashPreview,
              style: const TextStyle(color: AppTheme.accentPurple, fontSize: 20,
                  fontFamily: 'monospace', fontWeight: FontWeight.bold, letterSpacing: 4)),
        ]),
        const Spacer(),
        IconButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: _hashPreview));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Fingerprint copied'),
              duration: Duration(seconds: 1),
            ));
          },
          icon: const Icon(Icons.copy, color: AppTheme.textDim, size: 17),
        ),
      ]),
    );
  }

  Widget _buildPlatformCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: AppTheme.bgCard,
        border: Border.all(color: AppTheme.borderGlow),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('PLATFORM CAPABILITIES',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 10,
                fontWeight: FontWeight.bold, letterSpacing: 2)),
        const SizedBox(height: 12),
        _capRow('Platform', AppPlatform.name),
        _capRow('Bluetooth Classic (SPP)',
            AppPlatform.supportsClassicBluetooth ? '✓ Supported' : '✗ Not available',
            color: AppPlatform.supportsClassicBluetooth
                ? AppTheme.accentGreen : AppTheme.textDim),
        _capRow('Bluetooth LE (BLE)',
            AppPlatform.supportsBLE ? '✓ Supported' : '✗ Not available',
            color: AppPlatform.supportsBLE ? AppTheme.accentGreen : AppTheme.textDim),
        _capRow('Runtime permissions',
            AppPlatform.needsRuntimePermissions ? 'Required' : 'Not required',
            color: AppTheme.textSecondary),
      ]),
    );
  }

  Widget _capRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(children: [
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        const Spacer(),
        Text(value, style: TextStyle(
            color: color ?? AppTheme.textPrimary,
            fontSize: 12, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  Widget _buildTips() {
    const tips = [
      ('🔐', 'Share the passphrase with your contact via a secure, out-of-band channel.'),
      ('🔄', 'Change passphrases regularly and after each session for better security.'),
      ('📋', 'Compare fingerprints on both devices — they must match exactly.'),
      ('⚠️', 'Messages encrypted with a different passphrase cannot be decrypted.'),
      ('🔀', 'v2 uses a random IV per message, preventing ciphertext analysis.'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('SECURITY NOTES',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 10,
              fontWeight: FontWeight.bold, letterSpacing: 2)),
      const SizedBox(height: 12),
      ...tips.map((t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.$1, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 10),
          Expanded(child: Text(t.$2,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.5))),
        ]),
      )),
    ]);
  }

  void _generatePassphrase() {
    final p = EncryptionService.generatePassphrase();
    _passphraseCtrl.text = p;
    setState(() { _hashPreview = EncryptionService.hashPreview(p); _obscure = false; });
  }

  Future<void> _applyPassphrase() async {
    final p = _passphraseCtrl.text.trim();
    if (p.isEmpty) return;
    context.read<BluetoothService>().updatePassphrase(p);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('passphrase', p);
    setState(() { _hashPreview = EncryptionService.hashPreview(p); _saved = true; });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Passphrase updated and saved'),
        backgroundColor: AppTheme.accentGreen.withOpacity(0.9),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ));
    }
  }
}
