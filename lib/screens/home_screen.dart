import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../platform/app_platform.dart';
import '../platform/permission_helper.dart';
import '../services/bluetooth_service.dart';
import '../services/wifi_service.dart';
import '../models/device_model.dart';
import '../theme/app_theme.dart';
import '../widgets/bt_signal_bars.dart';
import '../widgets/glow_container.dart';
import '../widgets/scan_animation.dart';
import '../widgets/platform_badge.dart';
import '../widgets/wifi_connection_dialog.dart';
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
  String? _bootError;

  late WifiService _wifiService;
  bool _wasWifiConnected = false;

  @override
  void initState() {
    super.initState();
    _wifiService = context.read<WifiService>();
    _wifiService.addListener(_onWifiStateChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    _wifiService.removeListener(_onWifiStateChanged);
    super.dispose();
  }

  // 🟢 FIX: Safer navigation handling to prevent tearing down unintended routes
  void _onWifiStateChanged() {
    if (!mounted) return;
    final bool isConnected = _wifiService.isConnected;
    final bool isWide = MediaQuery.sizeOf(context).width >= 720;

    if (isConnected && !_wasWifiConnected) {
      if (!isWide) {
        final nav = Navigator.of(context);
        if (nav.canPop()) {
          nav.popUntil((route) => route.isFirst);
        }
        nav.push(
          MaterialPageRoute(builder: (_) => const ChatScreen()),
        );
      }
    }

    _wasWifiConnected = isConnected;
  }

  Future<void> _boot() async {
    try {
      if (AppPlatform.isWeb) {
        if (mounted) setState(() => _initialized = true);
        return;
      }

      if (AppPlatform.needsRuntimePermissions) {
        bool granted = false;
        try {
          granted = await PermissionHelper.requestAllPermissions();
        } catch (e) {
          debugPrint('[Boot] Permission request failed: $e');
        }

        if (!granted && mounted) {
          setState(() {
            _permissionDenied = true;
            _initialized = true;
          });
          return;
        }
      }

      if (!mounted) return;
      setState(() => _permissionDenied = false);

      try {
        await context.read<BluetoothService>().initialize();
      } catch (e) {
        debugPrint('[Boot] BluetoothService.initialize failed: $e');
      }
    } catch (e) {
      debugPrint('[Boot] Unexpected error: $e');
      if (mounted) setState(() => _bootError = e.toString());
    } finally {
      if (mounted) setState(() => _initialized = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isWide = MediaQuery.sizeOf(context).width >= 720;

    // 🟢 PERF: Flattened Widget Tree. By watching at the top level,
    // we eliminate multiple nested Consumer2 widgets in the layout builders.
    final btService = context.watch<BluetoothService>();
    final wifiService = context.watch<WifiService>();

    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      appBar: _initialized && !_permissionDenied && _bootError == null
          ? _buildAppBar(context)
          : null,
      body: !_initialized
          ? _buildLoading()
          : _bootError != null
              ? _buildErrorScreen(_bootError!)
              : _permissionDenied
                  ? _buildPermissionDenied()
                  : isWide
                      ? _buildWideLayout(context, btService, wifiService)
                      : _buildNarrowLayout(context, btService, wifiService),
      floatingActionButton:
          _initialized && !_permissionDenied && _bootError == null && !isWide
              ? (btService.isConnected || wifiService.isConnected)
                  ? FloatingActionButton.extended(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ChatScreen()),
                      ),
                      backgroundColor: AppTheme.accentGreen,
                      icon: const Icon(Icons.chat, color: AppTheme.bgDeep),
                      label: const Text(
                        'RESUME SESSION',
                        style: TextStyle(
                          color: AppTheme.bgDeep,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    )
                  : null
              : null,
    );
  }

  // ── AppBar ───────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: AppTheme.bgDeep,
      elevation: 0,
      titleSpacing: 16,
      title: Row(
        children: [
          _PulseDot(),
          const SizedBox(width: 10),
          const Text(
            'BT TERMINAL',
            style: TextStyle(
              letterSpacing: 2,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 10),
          const PlatformBadge(),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.wifi, color: AppTheme.accentCyan, size: 22),
          tooltip: 'WLAN Fallback',
          onPressed: () => WifiConnectionDialog.show(context),
        ),
        IconButton(
          icon: const Icon(Icons.security_outlined,
              color: AppTheme.accentCyan, size: 22),
          tooltip: 'Security Settings',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          ),
        ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                AppTheme.accentCyan.withValues(alpha: 0.4),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Layouts ──────────────────────────────────────────────

  Widget _buildNarrowLayout(
      BuildContext context, BluetoothService bt, WifiService wifi) {
    return Column(
      children: [
        _buildStatusBar(bt, wifi),
        Expanded(child: _buildScrollContent(context, bt)),
      ],
    );
  }

  Widget _buildWideLayout(
      BuildContext context, BluetoothService bt, WifiService wifi) {
    return Row(
      children: [
        SizedBox(
          width: 340,
          child: Column(
            children: [
              _buildStatusBar(bt, wifi),
              Expanded(child: _buildScrollContent(context, bt)),
            ],
          ),
        ),
        Container(width: 1, color: AppTheme.borderGlow),
        Expanded(
          child: (bt.isConnected || wifi.isConnected)
              ? const ChatScreen()
              : _buildWidePlaceholder(),
        ),
      ],
    );
  }

  Widget _buildWidePlaceholder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bluetooth_searching,
            color: AppTheme.accentCyan.withValues(alpha: 0.06),
            size: 120,
          ),
          const SizedBox(height: 20),
          const Text(
            'AWAITING UPLINK',
            style: TextStyle(
              color: AppTheme.textDim,
              fontSize: 11,
              letterSpacing: 3,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Connect a device to begin secure session',
            style: TextStyle(color: AppTheme.textDim, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildScrollContent(BuildContext context, BluetoothService service) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      children: [
        if (AppPlatform.isWeb) ...[
          _buildWebBanner(),
          const SizedBox(height: 12),
        ],
        _buildScanButton(service),
        if (service.errorMessage != null) ...[
          const SizedBox(height: 8),
          _buildErrorBanner(service),
        ],
        if (service.pairedDevices.isNotEmpty) ...[
          const SizedBox(height: 28),
          _buildSectionHeader('BONDED NODES', Icons.link, AppTheme.accentGreen),
          const SizedBox(height: 10),
          ...service.pairedDevices
              .asMap()
              .entries
              .map((e) => _buildDeviceTile(context, e.value, service, e.key)),
        ],
        if (service.discovered.isNotEmpty) ...[
          const SizedBox(height: 28),
          _buildSectionHeader(
              'NEARBY NODES', Icons.wifi_tethering, AppTheme.accentCyan),
          const SizedBox(height: 10),
          ...service.discovered
              .asMap()
              .entries
              .map((e) => _buildDeviceTile(context, e.value, service, e.key)),
        ],
        if (!AppPlatform.isWeb &&
            service.pairedDevices.isEmpty &&
            service.discovered.isEmpty &&
            !service.isDiscovering) ...[
          const SizedBox(height: 40),
          _buildEmptyHint(),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String label, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 12),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: color.withValues(alpha: 0.8),
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 2.5,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color.withValues(alpha: 0.3), Colors.transparent],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBar(BluetoothService service, WifiService wifi) {
    final bool isWeb = AppPlatform.isWeb;

    String label;
    Color color;
    String? connectedName;

    if (wifi.isConnected) {
      label = 'WLAN SECURE LINK';
      color = AppTheme.accentGreen;
      connectedName = wifi.localIP ?? 'Direct Link';
    } else if (isWeb) {
      label = 'WEB — BLUETOOTH UNAVAILABLE';
      color = AppTheme.warning;
    } else {
      label = service.state.name.toUpperCase();
      color = service.state == BtConnectionState.connected
          ? AppTheme.accentGreen
          : service.state == BtConnectionState.error
              ? AppTheme.danger
              : service.state == BtConnectionState.scanning
                  ? AppTheme.accentCyan
                  : AppTheme.textSecondary;
      if (service.isConnected) {
        connectedName = service.connectedDeviceName;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface.withValues(alpha: 0.6),
        border: Border(
          bottom: BorderSide(color: color.withValues(alpha: 0.15)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 4),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          if (connectedName != null) ...[
            const Spacer(),
            Text(
              connectedName,
              style: const TextStyle(
                color: AppTheme.accentGreen,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.lock, size: 10, color: AppTheme.accentGreen),
          ],
        ],
      ),
    );
  }

  Widget _buildScanButton(BluetoothService service) {
    final bool disabled = AppPlatform.isWeb;
    final bool scanning = service.isDiscovering;

    return GlowContainer(
      glowColor: disabled ? Colors.transparent : AppTheme.accentCyan,
      blurRadius: scanning ? 20 : 10,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          // 🟢 FIX: explicitly disable splash ripple when running on Web
          splashColor: disabled ? Colors.transparent : null,
          highlightColor: disabled ? Colors.transparent : null,
          onTap: disabled
              ? null
              : scanning
                  ? service.stopDiscovery
                  : service.startDiscovery,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: AppTheme.bgSurface.withValues(alpha: 0.5),
              border: Border.all(
                color: disabled
                    ? AppTheme.borderGlow.withValues(alpha: 0.3)
                    : scanning
                        ? AppTheme.accentCyan.withValues(alpha: 0.6)
                        : AppTheme.borderGlow,
                width: scanning ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                if (scanning)
                  const RepaintBoundary(child: ScanAnimation(size: 40))
                else
                  Icon(
                    disabled ? Icons.bluetooth_disabled : Icons.radar,
                    color: disabled ? AppTheme.textDim : AppTheme.accentCyan,
                    size: 26,
                  ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        disabled
                            ? 'BLUETOOTH UNAVAILABLE'
                            : scanning
                                ? 'SCANNING...'
                                : 'SCAN FOR DEVICES',
                        style: TextStyle(
                          color:
                              disabled ? AppTheme.textDim : AppTheme.accentCyan,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        disabled
                            ? 'Use Android or iOS app'
                            : scanning
                                ? 'Tap to stop'
                                : 'Classic BT + BLE',
                        style: const TextStyle(
                          color: AppTheme.textDim,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!disabled)
                  Icon(
                    scanning ? Icons.stop_circle_outlined : Icons.chevron_right,
                    color: scanning ? AppTheme.danger : AppTheme.textDim,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceTile(BuildContext context, BTDevice device,
      BluetoothService service, int index) {
    final bool isConnecting = service.state == BtConnectionState.connecting;

    return Padding(
      // 🟢 FIX: Added ValueKey bounded to MAC address to stop list rebuilds
      // from re-triggering the entrance animation every time the signal strength updates.
      key: ValueKey(device.address),
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: isConnecting ? null : () => _connect(context, device, service),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: AppTheme.bgCard,
              border: Border.all(color: AppTheme.borderGlow),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (device.isBLE
                            ? AppTheme.accentCyan
                            : AppTheme.accentGreen)
                        .withValues(alpha: 0.1),
                    border: Border.all(
                      color: (device.isBLE
                              ? AppTheme.accentCyan
                              : AppTheme.accentGreen)
                          .withValues(alpha: 0.3),
                    ),
                  ),
                  child: Icon(
                    device.isBLE ? Icons.bluetooth : Icons.bluetooth_connected,
                    size: 18,
                    color: device.isBLE
                        ? AppTheme.accentCyan
                        : AppTheme.accentGreen,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            device.displayAddress,
                            style: const TextStyle(
                              color: AppTheme.textDim,
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: (device.isBLE
                                      ? AppTheme.accentCyan
                                      : AppTheme.accentGreen)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              device.isBLE ? 'BLE' : 'SPP',
                              style: TextStyle(
                                color: device.isBLE
                                    ? AppTheme.accentCyan
                                    : AppTheme.accentGreen,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (device.rssi != null) ...[
                            const SizedBox(width: 8),
                            BTSignalBars(bars: device.signalInfo.bars),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.accentCyan.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppTheme.accentCyan.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    isConnecting ? '...' : 'LINK',
                    style: const TextStyle(
                      color: AppTheme.accentCyan,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    )
        .animate(key: ValueKey('anim_${device.address}'))
        .fadeIn(duration: 200.ms, delay: (index * 50).ms)
        .slideY(
          begin: 0.1,
          end: 0,
          duration: 200.ms,
          delay: (index * 50).ms,
        );
  }

  Future<void> _connect(
      BuildContext context, BTDevice device, BluetoothService service) async {
    final navigator = Navigator.of(context);
    final bool isWide = MediaQuery.sizeOf(context).width >= 720;

    await service.stopDiscovery();
    await service.connectToDevice(device);

    if (!mounted) return;

    if (service.isConnected && !isWide) {
      navigator.push(MaterialPageRoute(builder: (_) => const ChatScreen()));
    }
  }

  // ── State / Info Widgets ─────────────────────────────────

  Widget _buildWebBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: AppTheme.warning, size: 16),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Bluetooth is not supported on Web. '
              'Use the Android or iOS app for full functionality.',
              style:
                  TextStyle(color: AppTheme.warning, fontSize: 11, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyHint() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sensors,
              size: 48, color: AppTheme.textDim.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          const Text(
            'No devices found',
            style: TextStyle(color: AppTheme.textDim, fontSize: 12),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tap SCAN to search for nearby devices',
            style: TextStyle(color: AppTheme.textDim, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RepaintBoundary(child: ScanAnimation(size: 90)),
            SizedBox(height: 20),
            Text(
              'INITIALIZING',
              style: TextStyle(
                color: AppTheme.textDim,
                fontSize: 10,
                letterSpacing: 3,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );

  Widget _buildPermissionDenied() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.danger.withValues(alpha: 0.1),
                  border:
                      Border.all(color: AppTheme.danger.withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.bluetooth_disabled,
                    color: AppTheme.danger, size: 48),
              ),
              const SizedBox(height: 24),
              const Text(
                'ACCESS DENIED',
                style: TextStyle(
                  color: AppTheme.danger,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Bluetooth and Location permissions\nare required to operate.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: PermissionHelper.openSettings,
                icon: const Icon(Icons.settings, size: 16),
                label: const Text('OPEN SETTINGS'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.danger,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildErrorScreen(String error) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppTheme.danger, size: 56),
              const SizedBox(height: 20),
              const Text(
                'BOOT ERROR',
                style: TextStyle(
                  color: AppTheme.danger,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.borderGlow),
                ),
                child: Text(
                  error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    height: 1.6,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _initialized = false;
                    _bootError = null;
                  });
                  _boot();
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('RETRY'),
              ),
            ],
          ),
        ),
      );

  Widget _buildErrorBanner(BluetoothService service) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.danger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppTheme.danger, size: 14),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                service.errorMessage ?? 'Unknown Error',
                style: const TextStyle(color: AppTheme.danger, fontSize: 11),
              ),
            ),
          ],
        ),
      );
}

class _PulseDot extends StatefulWidget {
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _anim = Tween(begin: 0.4, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.accentCyan,
          boxShadow: [
            BoxShadow(
              color: AppTheme.accentCyan.withValues(alpha: _anim.value * 0.8),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ],
        ),
      ),
    );
  }
}
