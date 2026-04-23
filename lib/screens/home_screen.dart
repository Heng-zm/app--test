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
    // Safety: ensure boot starts after the first frame is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    // 1. Request the full set of permissions (BT, Camera, Photos, etc.)
    if (AppPlatform.needsRuntimePermissions) {
      final granted = await PermissionHelper.requestAllPermissions();
      if (!granted && mounted) {
        setState(() {
          _permissionDenied = true;
          _initialized = true;
        });
        return;
      }
    }

    if (!mounted) return;

    // Reset flags if retrying from a denied state
    setState(() {
      _permissionDenied = false;
    });

    // 2. Initialize the Bluetooth Hardware
    final service = context.read<BluetoothService>();
    await service.initialize();

    if (mounted) {
      setState(() => _initialized = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Responsive breakpoint: 720px for Tablet/Desktop side-by-side view
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
      elevation: 0,
      title: Row(children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.accentCyan,
            boxShadow: [
              BoxShadow(
                color: AppTheme.accentCyan.withOpacity(0.7),
                blurRadius: 8,
                spreadRadius: 2,
              )
            ],
          ),
        ),
        const SizedBox(width: 12),
        const Text('BT SECURECHAT',
            style: TextStyle(
                letterSpacing: 1.5, fontSize: 16, fontWeight: FontWeight.bold)),
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
              AppTheme.accentCyan.withOpacity(0.3),
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
        return Row(children: [
          // Left panel: Device Discovery (Fixed Width)
          SizedBox(
            width: 340,
            child: Column(children: [
              _buildStatusBar(service),
              Expanded(child: _buildScrollContent(context, service)),
            ]),
          ),
          Container(width: 1, color: AppTheme.borderGlow),

          // Right panel: In-line Chat Screen (Standard Tablet UX)
          Expanded(
            child: service.isConnected
                ? const ChatScreen()
                : _buildWidePlaceholder(),
          ),
        ]);
      },
    );
  }

  Widget _buildWidePlaceholder() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.bluetooth_searching,
            color: AppTheme.accentCyan.withOpacity(0.05), size: 160),
        const SizedBox(height: 24),
        const Text(
          'Node inactive.\nSelect a nearby target to establish\nan encrypted communication uplink.',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: AppTheme.textDim,
              fontSize: 13,
              height: 1.6,
              letterSpacing: 0.5),
        ),
      ]),
    );
  }

  // ── Content Components ──────────────────────────────────────────────────

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
          const SizedBox(height: 24),
          _buildSectionHeader('BONDED NODES', Icons.devices),
          const SizedBox(height: 12),
          ...service.pairedDevices
              .map((d) => _buildDeviceTile(context, d, service)),
        ],
        if (service.discovered.isNotEmpty) ...[
          const SizedBox(height: 24),
          _buildSectionHeader('DISCOVERED NODES', Icons.radar),
          const SizedBox(height: 12),
          ...service.discovered
              .map((d) => _buildDeviceTile(context, d, service)),
        ],
        if (service.isDiscovering && service.discovered.isEmpty) ...[
          const SizedBox(height: 48),
          _buildScanningPlaceholder(),
        ],
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildStatusBar(BluetoothService service) {
    Color color;
    String text;
    IconData icon;
    switch (service.state) {
      case BtConnectionState.connecting:
        color = AppTheme.warning;
        text = 'CONNECTING...';
        icon = Icons.bluetooth_searching;
        break;
      case BtConnectionState.scanning:
        color = AppTheme.accentCyan;
        text = 'SCANNING';
        icon = Icons.radar;
        break;
      case BtConnectionState.connected:
        color = AppTheme.accentGreen;
        text = 'CONNECTED';
        icon = Icons.bluetooth_connected;
        break;
      case BtConnectionState.error:
        color = AppTheme.danger;
        text = 'HARDWARE ERROR';
        icon = Icons.error_outline;
        break;
      default:
        color = AppTheme.textDim;
        text = 'SYSTEM READY';
        icon = Icons.bluetooth;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        border: Border(bottom: BorderSide(color: color.withOpacity(0.15))),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 13),
        const SizedBox(width: 8),
        Text(text,
            style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.accentCyan.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text('AES-256 E2EE',
              style: TextStyle(
                  color: AppTheme.accentCyan,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5)),
        ),
      ]),
    );
  }

  Widget _buildScanButton(BluetoothService service) {
    final bool isScanning = service.isDiscovering;
    return GlowContainer(
      child: InkWell(
        onTap: isScanning ? service.stopDiscovery : service.startDiscovery,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.bgCard, AppTheme.bgSurface],
            ),
            border: Border.all(
                color: isScanning
                    ? AppTheme.accentCyan.withOpacity(0.5)
                    : AppTheme.borderGlow),
          ),
          child: Row(children: [
            isScanning
                ? const RepaintBoundary(child: ScanAnimation(size: 48))
                : const Icon(Icons.bluetooth_searching,
                    color: AppTheme.accentCyan, size: 32),
            const SizedBox(width: 16),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(isScanning ? 'SEARCHING FOR TARGETS' : 'INITIATE SCAN',
                      style: const TextStyle(
                          color: AppTheme.accentCyan,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1)),
                  const SizedBox(height: 4),
                  Text(
                      isScanning
                          ? 'Monitoring radio bands · ${service.discovered.length} detected'
                          : 'Discover nearby hardware endpoints',
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11)),
                ])),
            Icon(
                isScanning
                    ? Icons.stop_circle_outlined
                    : Icons.play_circle_outline,
                color: isScanning ? AppTheme.danger : AppTheme.accentCyan,
                size: 28),
          ]),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(children: [
      Icon(icon, size: 12, color: AppTheme.textSecondary),
      const SizedBox(width: 8),
      Text(title,
          style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 2)),
      const SizedBox(width: 10),
      const Expanded(child: Divider(color: AppTheme.borderGlow, height: 1)),
    ]);
  }

  Widget _buildDeviceTile(
      BuildContext context, BTDevice device, BluetoothService service) {
    final bool isConnecting = service.state == BtConnectionState.connecting;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: AppTheme.bgCard,
        border: Border.all(color: AppTheme.borderGlow),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(
            device.isBLE ? Icons.bluetooth_audio : Icons.phone_android,
            color: device.isPaired ? AppTheme.accentTeal : AppTheme.textDim),
        title: Text(device.name,
            style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600)),
        subtitle: Row(children: [
          Text(device.displayAddress,
              style: const TextStyle(
                  color: AppTheme.textDim,
                  fontSize: 10,
                  fontFamily: 'monospace')),
          const SizedBox(width: 8),
          if (device.rssi != null) BTSignalBars(bars: device.signalBars),
        ]),
        trailing: isConnecting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppTheme.accentCyan))
            : ElevatedButton(
                onPressed: () => _connect(context, device, service),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.bgSurface,
                  foregroundColor: AppTheme.accentCyan,
                  side:
                      const BorderSide(color: AppTheme.accentCyan, width: 0.5),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 30),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('CONNECT',
                    style:
                        TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              ),
      ),
    );
  }

  Widget _buildScanningPlaceholder() {
    return Column(children: [
      const RepaintBoundary(child: ScanAnimation(size: 80)),
      const SizedBox(height: 16),
      Text('POLLING FREQUENCIES...',
          style: TextStyle(
              color: AppTheme.accentCyan.withOpacity(0.5),
              fontSize: 10,
              letterSpacing: 2,
              fontWeight: FontWeight.bold)),
    ]);
  }

  Widget _buildErrorBanner(BluetoothService service) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: AppTheme.danger.withOpacity(0.1),
        border: Border.all(color: AppTheme.danger.withOpacity(0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded,
            color: AppTheme.danger, size: 18),
        const SizedBox(width: 12),
        Expanded(
            child: Text(service.errorMessage ?? 'Radio Link Failure',
                style: const TextStyle(color: AppTheme.danger, fontSize: 12))),
        IconButton(
            onPressed: service.clearError,
            icon: const Icon(Icons.close, size: 16, color: AppTheme.danger)),
      ]),
    );
  }

  Widget _buildLoading() {
    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const RepaintBoundary(child: ScanAnimation(size: 100)),
          const SizedBox(height: 24),
          const Text('INITIALIZING SECURE PROTOCOLS',
              style: TextStyle(
                  color: AppTheme.accentCyan,
                  fontSize: 10,
                  letterSpacing: 2,
                  fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  Widget _buildPermissionDenied() {
    return Center(
        child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.security_update_warning,
            color: AppTheme.danger, size: 64),
        const SizedBox(height: 24),
        const Text('CRITICAL SECURITY PERMISSION DENIED',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1)),
        const SizedBox(height: 12),
        const Text(
          'SecureChat requires Bluetooth and hardware access to establish encrypted links. This app cannot function without these parameters.',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: AppTheme.textSecondary, fontSize: 12, height: 1.6),
        ),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: () async {
            await PermissionHelper.openSettings();
            _boot(); // Retry boot after returning from settings
          },
          child: const Text('MANUAL OVERRIDE (SETTINGS)'),
        ),
      ]),
    ));
  }

  // BUG FIX: Navigation is now a direct, safe result of a user action.
  Future<void> _connect(
      BuildContext context, BTDevice device, BluetoothService service) async {
    await service.stopDiscovery();
    await service.connectToDevice(device);

    if (!mounted) return;

    if (service.isConnected) {
      final isWide = MediaQuery.of(context).size.width >= 720;
      // Navigate only on Mobile. Tablet layout uses a Widget Switcher in the build method.
      if (!isWide) {
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => const ChatScreen()));
      }
    }
  }
}
