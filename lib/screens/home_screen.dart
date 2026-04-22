import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../platform/app_platform.dart';
import '../platform/permission_helper.dart';
import '../services/bluetooth_service.dart';
import '../models/device_model.dart';
import '../theme/app_theme.dart';
import '../widgets/bt_signal_bars.dart';
import '../widgets/glow_container.dart';
import '../widgets/scan_animation.dart';
import '../widgets/platform_badge.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _initialized = false;
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    // Request permissions only on platforms that need them
    if (AppPlatform.needsRuntimePermissions) {
      final granted = await PermissionHelper.requestBluetoothPermissions();
      if (!granted && mounted) {
        setState(() {
          _permissionDenied = true;
          _initialized = true;
        });
        return;
      }
    }

    if (!mounted) return;
    final service = context.read<BluetoothService>();
    await service.initialize();
    if (mounted) setState(() => _initialized = true);
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 720;

    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      appBar: _buildAppBar(context),
      body: !_initialized
          ? _buildLoading()
          : _permissionDenied
              ? _buildPermissionDenied()
              : isWide
                  ? _buildWideLayout(context)
                  : _buildNarrowLayout(context),
    );
  }

  // ── AppBar ──────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: AppTheme.bgDeep,
      title: Row(children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.accentCyan,
            boxShadow: [BoxShadow(color: AppTheme.accentCyan.withOpacity(0.7), blurRadius: 8, spreadRadius: 2)],
          ),
        ),
        const SizedBox(width: 10),
        const Text('BT SECURECHAT'),
        const SizedBox(width: 10),
        const PlatformBadge(),
      ]),
      actions: [
        IconButton(
          icon: const Icon(Icons.security, color: AppTheme.accentCyan),
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SettingsScreen())),
          tooltip: 'Security Settings',
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              Colors.transparent,
              AppTheme.accentCyan.withOpacity(0.5),
              Colors.transparent,
            ]),
          ),
        ),
      ),
    );
  }

  // ── Layouts ─────────────────────────────────────────────────────────────
  Widget _buildNarrowLayout(BuildContext context) {
    return Consumer<BluetoothService>(
      builder: (context, service, _) {
        _navigateToChatIfConnected(context, service);
        return Column(children: [
          _buildStatusBar(service),
          Expanded(child: _buildScrollContent(context, service)),
        ]);
      },
    );
  }

  Widget _buildWideLayout(BuildContext context) {
    return Consumer<BluetoothService>(
      builder: (context, service, _) {
        _navigateToChatIfConnected(context, service);
        return Row(children: [
          // Left panel: scan + device list
          SizedBox(
            width: 340,
            child: Column(children: [
              _buildStatusBar(service),
              Expanded(child: _buildScrollContent(context, service)),
            ]),
          ),
          Container(width: 1, color: AppTheme.borderGlow),
          // Right panel: placeholder / chat preview
          Expanded(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.bluetooth, color: AppTheme.textDim, size: 48),
                const SizedBox(height: 16),
                Text(
                  service.isConnected
                      ? 'Connected to ${service.connectedDeviceName}'
                      : 'Select a device to start chatting',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                ),
                if (service.isConnected) ...[
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const ChatScreen())),
                    child: const Text('OPEN CHAT'),
                  ),
                ],
              ]),
            ),
          ),
        ]);
      },
    );
  }

  void _navigateToChatIfConnected(BuildContext context, BluetoothService service) {
    if (service.isConnected && MediaQuery.of(context).size.width < 720) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pushReplacement(context,
              MaterialPageRoute(builder: (_) => const ChatScreen()));
        }
      });
    }
  }

  // ── Content ─────────────────────────────────────────────────────────────
  Widget _buildScrollContent(BuildContext context, BluetoothService service) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildScanButton(service),
        if (service.errorMessage != null) ...[
          const SizedBox(height: 12),
          _buildErrorBanner(service),
        ],
        if (service.pairedDevices.isNotEmpty) ...[
          const SizedBox(height: 20),
          _buildSectionHeader('PAIRED DEVICES', Icons.devices),
          const SizedBox(height: 10),
          ...service.pairedDevices.map((d) => _buildDeviceTile(context, d, service)),
        ],
        if (service.discovered.isNotEmpty) ...[
          const SizedBox(height: 20),
          _buildSectionHeader('NEARBY DEVICES', Icons.bluetooth_searching),
          const SizedBox(height: 10),
          ...service.discovered.map((d) => _buildDeviceTile(context, d, service)),
        ],
        if (service.isDiscovering && service.discovered.isEmpty) ...[
          const SizedBox(height: 32),
          _buildScanningPlaceholder(),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Widgets ─────────────────────────────────────────────────────────────
  Widget _buildStatusBar(BluetoothService service) {
    Color color;
    String text;
    IconData icon;
    switch (service.state) {
      case BtConnectionState.connecting:
        color = AppTheme.warning; text = 'CONNECTING...'; icon = Icons.bluetooth_searching;
      case BtConnectionState.scanning:
        color = AppTheme.accentCyan; text = 'SCANNING'; icon = Icons.radar;
      case BtConnectionState.connected:
        color = AppTheme.accentGreen; text = 'CONNECTED'; icon = Icons.bluetooth_connected;
      case BtConnectionState.error:
        color = AppTheme.danger; text = 'ERROR'; icon = Icons.error_outline;
      default:
        color = AppTheme.textDim; text = 'READY'; icon = Icons.bluetooth;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        border: Border(bottom: BorderSide(color: color.withOpacity(0.2))),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 13),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.accentCyan.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text('AES-256 · RANDOM IV',
              style: TextStyle(color: AppTheme.accentCyan.withOpacity(0.7), fontSize: 9, letterSpacing: 1)),
        ),
      ]),
    );
  }

  Widget _buildScanButton(BluetoothService service) {
    final scanning = service.isDiscovering;
    return GlowContainer(
      child: InkWell(
        onTap: scanning ? service.stopDiscovery : service.startDiscovery,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [AppTheme.bgCard, AppTheme.bgSurface],
            ),
            border: Border.all(
              color: scanning ? AppTheme.accentCyan.withOpacity(0.5) : AppTheme.borderGlow,
            ),
          ),
          child: Row(children: [
            scanning
                ? const ScanAnimation(size: 52)
                : Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.accentCyan.withOpacity(0.1),
                      border: Border.all(color: AppTheme.accentCyan.withOpacity(0.35)),
                    ),
                    child: const Icon(Icons.bluetooth_searching, color: AppTheme.accentCyan, size: 26),
                  ),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                scanning ? 'SCANNING...' : 'SCAN FOR DEVICES',
                style: const TextStyle(color: AppTheme.accentCyan, fontSize: 13,
                    fontWeight: FontWeight.bold, letterSpacing: 1.5),
              ),
              const SizedBox(height: 3),
              Text(
                scanning
                    ? 'Tap to stop · ${service.discovered.length} found'
                    : AppPlatform.supportsClassicBluetooth
                        ? 'Classic + BLE scan'
                        : 'BLE scan',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
              ),
            ])),
            Icon(
              scanning ? Icons.stop_circle : Icons.play_circle,
              color: scanning ? AppTheme.danger : AppTheme.accentCyan,
              size: 30,
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(children: [
      Icon(icon, size: 13, color: AppTheme.textSecondary),
      const SizedBox(width: 7),
      Text(title, style: const TextStyle(color: AppTheme.textSecondary,
          fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2)),
      const SizedBox(width: 10),
      const Expanded(child: Divider(color: AppTheme.borderGlow, height: 1)),
    ]);
  }

  Widget _buildDeviceTile(BuildContext context, BTDevice device, BluetoothService service) {
    final isConnecting = service.state == BtConnectionState.connecting;
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: AppTheme.bgCard,
        border: Border.all(color: AppTheme.borderGlow),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.bgSurface,
            border: Border.all(
              color: device.isPaired
                  ? AppTheme.accentTeal.withOpacity(0.5)
                  : AppTheme.borderGlow,
            ),
          ),
          child: Icon(
            device.isBLE ? Icons.bluetooth : Icons.phone_android,
            color: device.isPaired ? AppTheme.accentTeal : AppTheme.textSecondary,
            size: 18,
          ),
        ),
        title: Text(device.name,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Row(children: [
          Text(device.displayAddress,
              style: const TextStyle(color: AppTheme.textDim, fontSize: 10, fontFamily: 'monospace')),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: (device.isBLE ? AppTheme.accentPurple : AppTheme.accentTeal).withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              device.type,
              style: TextStyle(
                color: device.isBLE ? AppTheme.accentPurple : AppTheme.accentTeal,
                fontSize: 8, fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (device.rssi != null) ...[
            const SizedBox(width: 6),
            BTSignalBars(bars: device.signalBars),
          ],
        ]),
        trailing: isConnecting
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentCyan))
            : GestureDetector(
                onTap: () => _connect(context, device, service),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: AppTheme.accentCyan.withOpacity(0.5)),
                    color: AppTheme.accentCyan.withOpacity(0.07),
                  ),
                  child: const Text('CONNECT',
                      style: TextStyle(color: AppTheme.accentCyan, fontSize: 10,
                          fontWeight: FontWeight.bold, letterSpacing: 1)),
                ),
              ),
      ),
    );
  }

  Widget _buildScanningPlaceholder() {
    return Column(children: [
      const ScanAnimation(size: 72),
      const SizedBox(height: 14),
      Text('SEARCHING FOR DEVICES...',
          style: TextStyle(color: AppTheme.accentCyan.withOpacity(0.5),
              fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold)),
    ]);
  }

  Widget _buildErrorBanner(BluetoothService service) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: AppTheme.danger.withOpacity(0.09),
        border: Border.all(color: AppTheme.danger.withOpacity(0.35)),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline, color: AppTheme.danger, size: 17),
        const SizedBox(width: 10),
        Expanded(child: Text(service.errorMessage ?? '',
            style: const TextStyle(color: AppTheme.danger, fontSize: 12))),
        GestureDetector(
          onTap: service.clearError,
          child: const Icon(Icons.close, size: 15, color: AppTheme.danger),
        ),
      ]),
    );
  }

  Widget _buildLoading() {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const ScanAnimation(size: 110),
      const SizedBox(height: 22),
      Text('INITIALIZING BLUETOOTH',
          style: TextStyle(color: AppTheme.accentCyan.withOpacity(0.7),
              fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold)),
    ]));
  }

  Widget _buildPermissionDenied() {
    return Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.bluetooth_disabled, color: AppTheme.danger, size: 56),
        const SizedBox(height: 20),
        const Text('BLUETOOTH PERMISSION DENIED',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.danger, fontSize: 14,
                fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 12),
        const Text(
          'BT SecureChat needs Bluetooth and Location access to discover and connect to nearby devices.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () async {
            await PermissionHelper.openSettings();
            if (mounted) {
              setState(() { _initialized = false; _permissionDenied = false; });
              _boot();
            }
          },
          icon: const Icon(Icons.settings),
          label: const Text('OPEN SETTINGS'),
        ),
      ]),
    ));
  }

  Future<void> _connect(BuildContext context, BTDevice device, BluetoothService service) async {
    await service.stopDiscovery();
    await service.connectToDevice(device);
  }
}
