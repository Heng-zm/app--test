import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'models/message_model.dart';
import 'platform/app_platform.dart';
import 'services/bluetooth_service.dart';
import 'services/encryption_service.dart';
import 'services/wifi_service.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'theme/app_theme.dart';
import 'utils/permissions.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🛠️ PERFORMANCE: Request permissions in parallel with Hive initialization
  await Future.wait([
    requestPermissions(),
    Hive.initFlutter(),
  ]);

  // Register Hive Adapter
  if (!Hive.isAdapterRegistered(0)) {
    Hive.registerAdapter(MessageAdapter());
  }

  // 🛠️ FIX: Open the box once and keep a reference to it
  final messageBox = await Hive.openBox<Message>('messages');

  if (AppPlatform.isMobile) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  // Set System Overlay Styles (Android/iOS Status bar)
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

  runApp(BtSecureChatApp(messageBox: messageBox));
}

class BtSecureChatApp extends StatelessWidget {
  final Box<Message> messageBox;

  const BtSecureChatApp({super.key, required this.messageBox});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // 🛠️ PERF: Encryption service is a simple provider
        Provider(create: (_) => EncryptionService()),

        // 🛠️ FIX: Pass the Hive box to services so they can PERSIST messages
        ChangeNotifierProvider(
          lazy: false, // Force eager initialization of hardware
          create: (context) => BluetoothService(
            encryption: context.read<EncryptionService>(),
            // messageBox: messageBox, // Assuming you add this to your service constructor
          )..initialize(),
        ),

        ChangeNotifierProvider(
          lazy: false,
          create: (context) => WifiService(
            encryption: context.read<EncryptionService>(),
            // messageBox: messageBox, // Assuming you add this to your service constructor
          ),
        ),
      ],
      child: MaterialApp(
        title: 'BT SecureChat',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        // 🛠️ UX: Prevent system font scaling from breaking the "Terminal" look
        builder: (context, child) {
          return MediaQuery.withClampedTextScaling(
            minScaleFactor: 0.9,
            maxScaleFactor: 1.1,
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

  // 🛠️ PERF: Screens are marked const to prevent redundant rebuilds
  final List<Widget> _screens = const [
    HomeScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    // 🛠️ RESPONSIVENESS: Use sizeOf for better performance over .of(context).size
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width >= 720;

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
      // 🛠️ UI: Hide bottom bar on wide screens
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
