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
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    if (AppPlatform.needsRuntimePermissions) {
      final bool granted = await PermissionHelper.requestAllPermissions();
      if (!granted && mounted) {
        setState(() {
          _permissionDenied = true;
          _initialized = true;
        });
        return;
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _permissionDenied = false;
    });

    await context.read<BluetoothService>().initialize();

    if (mounted) {
      setState(() => _initialized = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isWide = MediaQuery.sizeOf(context).width >= 720;

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

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: AppTheme.bgDeep,
      elevation: 0,
      title: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.accentCyan,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.accentCyan.withValues(alpha: 0.7),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'BT TERMINAL',
            style: TextStyle(
              letterSpacing: 1.5,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 10),
          const PlatformBadge(),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.security, color: AppTheme.accentCyan),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                AppTheme.accentCyan.withValues(alpha: 0.3),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNarrowLayout(BuildContext context) {
    return Consumer<BluetoothService>(
      builder: (context, service, _) => Column(
        children: [
          _buildStatusBar(service),
          Expanded(child: _buildScrollContent(context, service)),
        ],
      ),
    );
  }

  Widget _buildWideLayout(BuildContext context) {
    return Consumer<BluetoothService>(
      builder: (context, service, _) => Row(
        children: [
          SizedBox(
            width: 340,
            child: Column(
              children: [
                _buildStatusBar(service),
                Expanded(child: _buildScrollContent(context, service)),
              ],
            ),
          ),
          Container(width: 1, color: AppTheme.borderGlow),
          Expanded(
            child: service.isConnected
                ? const ChatScreen()
                : _buildWidePlaceholder(),
          ),
        ],
      ),
    );
  }

  Widget _buildWidePlaceholder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bluetooth_searching,
            color: AppTheme.accentCyan.withValues(alpha: 0.05),
            size: 160,
          ),
          const SizedBox(height: 24),
          const Text(
            'Establish Uplink to Start Chat',
            style: TextStyle(color: AppTheme.textDim, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildScrollContent(BuildContext context, BluetoothService service) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildScanButton(service),
        // FIX: Removed braces from collection-if
        if (service.errorMessage != null) _buildErrorBanner(service),
        if (service.pairedDevices.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text(
            'BONDED NODES',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          ...service.pairedDevices
              .map((d) => _buildDeviceTile(context, d, service)),
        ],
        if (service.discovered.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text(
            'NEARBY NODES',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          ...service.discovered
              .map((d) => _buildDeviceTile(context, d, service)),
        ],
      ],
    );
  }

  Widget _buildStatusBar(BluetoothService service) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration:
          BoxDecoration(color: AppTheme.bgSurface.withValues(alpha: 0.5)),
      child: Row(
        children: [
          const Icon(Icons.radio_button_checked,
              color: AppTheme.accentGreen, size: 12),
          const SizedBox(width: 8),
          Text(
            service.state.name.toUpperCase(),
            style: const TextStyle(
              color: AppTheme.accentGreen,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanButton(BluetoothService service) {
    return GlowContainer(
      child: InkWell(
        onTap: service.isDiscovering
            ? service.stopDiscovery
            : service.startDiscovery,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: service.isDiscovering
                  ? AppTheme.accentCyan.withValues(alpha: 0.5)
                  : AppTheme.borderGlow,
            ),
          ),
          child: Row(
            children: [
              service.isDiscovering
                  ? const RepaintBoundary(child: ScanAnimation(size: 48))
                  : const Icon(Icons.search, color: AppTheme.accentCyan),
              const SizedBox(width: 16),
              const Text(
                'POLL FREQUENCIES',
                style: TextStyle(
                  color: AppTheme.accentCyan,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceTile(
      BuildContext context, BTDevice device, BluetoothService service) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      title: Text(
        device.name,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      subtitle: Row(
        children: [
          Text(
            device.displayAddress,
            style: const TextStyle(color: Colors.grey, fontSize: 10),
          ),
          const SizedBox(width: 8),
          // FIX: Removed braces from collection-if
          if (device.rssi != null) BTSignalBars(bars: device.signalBars),
        ],
      ),
      trailing: ElevatedButton(
        onPressed: () => _connect(context, device, service),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.bgSurface,
          foregroundColor: AppTheme.accentCyan,
        ),
        child: const Text('CONNECT', style: TextStyle(fontSize: 10)),
      ),
    );
  }

  Future<void> _connect(
      BuildContext context, BTDevice device, BluetoothService service) async {
    final navigator = Navigator.of(context);
    final bool isWide = MediaQuery.sizeOf(context).width >= 720;

    await service.stopDiscovery();
    await service.connectToDevice(device);

    if (!mounted) {
      return;
    }

    if (service.isConnected && !isWide) {
      navigator.push(MaterialPageRoute(builder: (_) => const ChatScreen()));
    }
  }

  Widget _buildErrorBanner(BluetoothService service) => Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: Text(
          service.errorMessage ?? 'Unknown Error',
          style: const TextStyle(color: Colors.red, fontSize: 12),
        ),
      );

  Widget _buildLoading() => const Scaffold(
      body: Center(child: RepaintBoundary(child: ScanAnimation(size: 100))));

  Widget _buildPermissionDenied() => const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32.0),
            child: Text(
              'Security Access Denied. Please enable permissions in settings.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      );
}
