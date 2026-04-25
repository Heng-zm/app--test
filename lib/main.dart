import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'models/message_model.dart';
import 'platform/app_platform.dart';
import 'platform/permission_helper.dart';
import 'services/bluetooth_service.dart';
import 'services/encryption_service.dart';
import 'services/wifi_service.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── 1. Atomic Initialization ──────────────────────────────────────────
  final initFutures = <Future<void>>[
    Hive.initFlutter(),
  ];
  if (AppPlatform.isMobile) {
    initFutures.add(
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
    );
  }
  await Future.wait(initFutures);

  // Register Adapters
  if (!Hive.isAdapterRegistered(0)) {
    Hive.registerAdapter(MessageAdapter());
  }

  // Open persistence box for chat logs
  final Box<Message> messageBox = await Hive.openBox<Message>('messages');

  // ── 2. Runtime Permissions ────────────────────────────────────────────
  // FIX: PermissionHelper was imported but never called — wired up here so
  // Bluetooth + Location permissions are requested before the UI starts and
  // the import is no longer flagged as unused.
  await PermissionHelper.requestAllPermissions();

  // ── 3. System UI Configuration ────────────────────────────────────────
  if (!AppPlatform.isWeb) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppTheme.bgDeep,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  runApp(BtSecureChatApp(messageBox: messageBox));
}

class BtSecureChatApp extends StatelessWidget {
  final Box<Message> messageBox;

  const BtSecureChatApp({super.key, required this.messageBox});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Core Logic Services
        Provider(create: (_) => EncryptionService()),

        // Expose the messageBox via Provider so descendant widgets can access
        // persisted messages.
        Provider<Box<Message>>.value(value: messageBox),

        ChangeNotifierProvider(
          lazy: false, // Eager init to start hardware listeners immediately
          create: (ctx) => BluetoothService(
            encryption: ctx.read<EncryptionService>(),
          ),
        ),

        ChangeNotifierProvider(
          lazy: false, // Eager init — WifiService binds sockets in constructor
          create: (ctx) => WifiService(
            encryption: ctx.read<EncryptionService>(),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'BT SecureChat',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        // ── Optimized Text Scaling ────────────────────────────────────────
        builder: (context, child) {
          final mediaQuery = MediaQuery.of(context);
          return MediaQuery(
            data: mediaQuery.copyWith(
              textScaler: mediaQuery.textScaler.clamp(
                minScaleFactor: 0.9,
                maxScaleFactor: 1.15,
              ),
            ),
            child: child!,
          );
        },
        home: const AppShell(),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = const [
      HomeScreen(),
      SettingsScreen(),
    ];
  }

  bool _isWide(Size size) => size.width >= 720;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isWide = _isWide(size);

    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      body: Row(
        children: [
          if (isWide) ...[
            NavigationRail(
              backgroundColor: AppTheme.bgSurface,
              selectedIndex: _index,
              onDestinationSelected: (idx) => setState(() => _index = idx),
              labelType: NavigationRailLabelType.all,
              indicatorColor: AppTheme.accentCyan.withValues(alpha: 0.1),
              selectedIconTheme:
                  const IconThemeData(color: AppTheme.accentCyan, size: 28),
              unselectedIconTheme:
                  const IconThemeData(color: AppTheme.textDim, size: 24),
              selectedLabelTextStyle: const TextStyle(
                color: AppTheme.accentCyan,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
              unselectedLabelTextStyle:
                  const TextStyle(color: AppTheme.textDim, fontSize: 11),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.terminal_outlined),
                  selectedIcon: Icon(Icons.terminal),
                  label: Text('TERMINAL'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.shield_outlined),
                  selectedIcon: Icon(Icons.shield),
                  label: Text('SECURITY'),
                ),
              ],
            ),
            const VerticalDivider(
                width: 1, thickness: 1, color: AppTheme.borderGlow),
          ],
          Expanded(
            child: IndexedStack(
              index: _index,
              children: _screens,
            ),
          ),
        ],
      ),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              height: 70,
              backgroundColor: AppTheme.bgSurface,
              selectedIndex: _index,
              elevation: 0,
              onDestinationSelected: (idx) => setState(() => _index = idx),
              indicatorColor: AppTheme.accentCyan.withValues(alpha: 0.1),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: const [
                NavigationDestination(
                  icon:
                      Icon(Icons.bluetooth_searching, color: AppTheme.textDim),
                  selectedIcon: Icon(Icons.bluetooth_searching,
                      color: AppTheme.accentCyan),
                  label: 'Terminal',
                ),
                NavigationDestination(
                  icon: Icon(Icons.security, color: AppTheme.textDim),
                  selectedIcon:
                      Icon(Icons.security, color: AppTheme.accentCyan),
                  label: 'Security',
                ),
              ],
            ),
    );
  }
}
