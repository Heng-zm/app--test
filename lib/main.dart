import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'models/message_model.dart';
import 'platform/app_platform.dart';
import 'services/bluetooth_service.dart';
import 'services/encryption_service.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  // Ensure the Flutter engine is initialized before hardware access
  WidgetsFlutterBinding.ensureInitialized();

  // ── Hive Persistence Initialization ───────────────────────────────────────
  // Setup local storage for session messages
  await Hive.initFlutter();
  if (!Hive.isAdapterRegistered(0)) {
    Hive.registerAdapter(MessageAdapter());
  }
  await Hive.openBox<Message>('messages');

  // ── Platform-Specific UI Configuration ────────────────────────────────────

  // Lock orientation for mobile users for a stable dashboard experience
  if (AppPlatform.isMobile) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  // Set system-level UI styles (Status Bar and Android Navigation Bar)
  if (!AppPlatform.isWeb) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppTheme.bgDeep,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  }

  runApp(const BtSecureChatApp());
}

class BtSecureChatApp extends StatelessWidget {
  const BtSecureChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // 1. Encryption Service handles the crypto logic
        Provider(create: (_) => EncryptionService()),

        // 2. Bluetooth Service depends on Encryption for sending/receiving
        ChangeNotifierProvider(
          create: (context) => BluetoothService(
            encryption: context.read<EncryptionService>(),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'BT SecureChat',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        builder: (context, child) {
          // Prevent very large accessibility text from breaking the UI layout
          return MediaQuery.withClampedTextScaling(
            minScaleFactor: 0.8,
            maxScaleFactor: 1.25,
            child: child!,
          );
        },
        home: const AppShell(),
      ),
    );
  }
}

/// The AppShell manages the top-level navigation and responsiveness.
/// It uses a side-bar (NavigationRail) on Tablets/Desktop and
/// a bottom-bar (NavigationBar) on Phones.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  // Primary views accessible via navigation
  final List<Widget> _screens = const [
    HomeScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    // 720px is the standard breakpoint for wide UI layouts
    final bool isWide = MediaQuery.of(context).size.width >= 720;

    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      body: Row(
        children: [
          // ── WIDE LAYOUT (TABLET / DESKTOP) ────────────────────────────────
          if (isWide) ...[
            NavigationRail(
              backgroundColor: AppTheme.bgSurface,
              selectedIndex: _index,
              onDestinationSelected: (idx) => setState(() => _index = idx),
              labelType: NavigationRailLabelType.all,
              indicatorColor: AppTheme.accentCyan.withOpacity(0.1),
              selectedIconTheme:
                  const IconThemeData(color: AppTheme.accentCyan, size: 28),
              unselectedIconTheme:
                  const IconThemeData(color: AppTheme.textDim, size: 24),
              selectedLabelTextStyle: const TextStyle(
                  color: AppTheme.accentCyan,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1),
              unselectedLabelTextStyle:
                  const TextStyle(color: AppTheme.textDim, fontSize: 11),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.bluetooth_searching),
                  label: Text('TERMINAL'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.security),
                  label: Text('ENCRYPTION'),
                ),
              ],
            ),
            const VerticalDivider(
                width: 1, thickness: 1, color: AppTheme.borderGlow),
          ],

          // Main Screen Content
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _screens[_index],
            ),
          ),
        ],
      ),

      // ── NARROW LAYOUT (MOBILE PHONE) ──────────────────────────────────────
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              height: 70,
              backgroundColor: AppTheme.bgSurface,
              selectedIndex: _index,
              onDestinationSelected: (idx) => setState(() => _index = idx),
              indicatorColor: AppTheme.accentCyan.withOpacity(0.1),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: const [
                NavigationDestination(
                  icon:
                      Icon(Icons.bluetooth_searching, color: AppTheme.textDim),
                  selectedIcon: Icon(Icons.bluetooth_searching,
                      color: AppTheme.accentCyan),
                  label: 'Connect',
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
