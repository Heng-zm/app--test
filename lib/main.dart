import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'models/message_model.dart';
import 'platform/app_platform.dart';
import 'services/bluetooth_service.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart'; // Added so we can use it in the nav
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Hive persistence ──────────────────────────────────────────────────────
  await Hive.initFlutter();
  Hive.registerAdapter(MessageAdapter());
  await Hive.openBox<Message>('messages');

  // ── Platform-specific UI config ───────────────────────────────────────────
  if (AppPlatform.isMobile) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  if (!AppPlatform.isWeb) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF070B14),
      ),
    );
  }

  runApp(const BtSecureChatApp());
}

class BtSecureChatApp extends StatelessWidget {
  const BtSecureChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BluetoothService(),
      child: MaterialApp(
        title: 'BT SecureChat',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        builder: (context, child) {
          // MODERN TEXT CLAMPING (Flutter 3.16+):
          // Replaces the manual TextScaler math with a built-in function
          return MediaQuery.withClampedTextScaling(
            minScaleFactor: 0.8,
            maxScaleFactor: 1.3,
            child: child!,
          );
        },
        home: const AppShell(),
      ),
    );
  }
}

/// Top-level shell: uses a NavigationRail on wide screens (desktop/tablet),
/// bottom nav on narrow screens (phone).
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  // Swapped the second HomeScreen placeholder with SettingsScreen
  static const _screens = [HomeScreen(), SettingsScreen()];

  @override
  Widget build(BuildContext context) {
    // Standardizing the wide breakpoint across the app
    final isWide = MediaQuery.of(context).size.width >= 720;

    // ── Wide Layout (Desktop / Tablet) ──────────────────────────────────────
    if (isWide) {
      return Scaffold(
        backgroundColor: AppTheme.bgDeep,
        body: Row(
          children: [
            NavigationRail(
              backgroundColor: AppTheme.bgSurface,
              selectedIndex: _index,
              onDestinationSelected: (int index) =>
                  setState(() => _index = index),
              selectedIconTheme:
                  const IconThemeData(color: AppTheme.accentCyan),
              unselectedIconTheme: const IconThemeData(color: AppTheme.textDim),
              selectedLabelTextStyle:
                  const TextStyle(color: AppTheme.accentCyan),
              unselectedLabelTextStyle:
                  const TextStyle(color: AppTheme.textDim),
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.bluetooth),
                  label: Text('Chat'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.security),
                  label: Text('Settings'),
                ),
              ],
            ),
            const VerticalDivider(
                thickness: 1, width: 1, color: AppTheme.borderGlow),
            Expanded(
              // Wrap with ClipRect to ensure child screens don't overflow into the rail
              child: ClipRect(child: _screens[_index]),
            ),
          ],
        ),
      );
    }

    // ── Narrow Layout (Mobile Phone) ────────────────────────────────────────
    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      body: _screens[_index],
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppTheme.bgSurface,
        indicatorColor: AppTheme.accentCyan.withOpacity(0.15),
        selectedIndex: _index,
        onDestinationSelected: (int index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.bluetooth, color: AppTheme.textDim),
            selectedIcon: Icon(Icons.bluetooth, color: AppTheme.accentCyan),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.security, color: AppTheme.textDim),
            selectedIcon: Icon(Icons.security, color: AppTheme.accentCyan),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
