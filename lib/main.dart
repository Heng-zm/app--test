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

Future<void> main() async {
  // 🟢 FIX: Call initialize without assigning to an unused variable
  WidgetsFlutterBinding.ensureInitialized();

  // ── 1. Early-Stage Initialization ─────────────────────────────────────
  await Future.wait([
    Hive.initFlutter(),
    if (AppPlatform.isMobile)
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
  ]);

  // Register Adapters
  if (!Hive.isAdapterRegistered(0)) {
    Hive.registerAdapter(MessageAdapter());
  }

  // Open persistence box
  final Box<Message> messageBox = await Hive.openBox<Message>('messages');

  // ── 2. System UI Configuration ────────────────────────────────────────
  if (!AppPlatform.isWeb) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
      ),
    );
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  // PERF: Limits memory overhead for the image-heavy chat sessions
  PaintingBinding.instance.imageCache.maximumSize = 100;

  runApp(BtSecureChatApp(messageBox: messageBox));
}

class BtSecureChatApp extends StatelessWidget {
  final Box<Message> messageBox;

  const BtSecureChatApp({super.key, required this.messageBox});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) => EncryptionService()),
        Provider<Box<Message>>.value(value: messageBox),
        ChangeNotifierProvider(
          lazy: false,
          create: (ctx) => BluetoothService(
            encryption: ctx.read<EncryptionService>(),
          ),
        ),
        ChangeNotifierProvider(
          lazy: false,
          create: (ctx) => WifiService(
            encryption: ctx.read<EncryptionService>(),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'BT TERMINAL',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        builder: (context, child) {
          final mediaQuery = MediaQuery.of(context);
          return MediaQuery(
            data: mediaQuery.copyWith(
              textScaler: mediaQuery.textScaler.clamp(
                minScaleFactor: 0.85,
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

  static const List<Widget> _screens = [
    HomeScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final bool isWide = size.width >= 720;

    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      extendBody: true,
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
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
              unselectedLabelTextStyle:
                  const TextStyle(color: AppTheme.textDim, fontSize: 10),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.radar_outlined),
                  selectedIcon: Icon(Icons.radar),
                  label: Text('TERMINAL'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.security_outlined),
                  selectedIcon: Icon(Icons.security),
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
          : Container(
              decoration: const BoxDecoration(
                border: Border(
                    top: BorderSide(color: AppTheme.borderGlow, width: 0.5)),
              ),
              child: NavigationBar(
                height: 65,
                backgroundColor: AppTheme.bgSurface,
                selectedIndex: _index,
                elevation: 0,
                onDestinationSelected: (idx) => setState(() => _index = idx),
                indicatorColor: AppTheme.accentCyan.withValues(alpha: 0.1),
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.radar, color: AppTheme.textDim),
                    selectedIcon: Icon(Icons.radar, color: AppTheme.accentCyan),
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
            ),
    );
  }
}
