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
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  if (!Hive.isAdapterRegistered(0)) {
    Hive.registerAdapter(MessageAdapter());
  }
  await Hive.openBox<Message>('messages');

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
        systemNavigationBarColor: AppTheme.bgDeep,
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
        Provider(create: (_) => EncryptionService()),
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

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 720;

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
                  const IconThemeData(color: AppTheme.accentCyan),
              unselectedIconTheme: const IconThemeData(color: AppTheme.textDim),
              selectedLabelTextStyle:
                  const TextStyle(color: AppTheme.accentCyan, fontSize: 12),
              unselectedLabelTextStyle:
                  const TextStyle(color: AppTheme.textDim, fontSize: 12),
              destinations: const [
                NavigationRailDestination(
                    icon: Icon(Icons.bluetooth), label: Text('TERMINAL')),
                NavigationRailDestination(
                    icon: Icon(Icons.security), label: Text('SECURITY')),
              ],
            ),
            const VerticalDivider(
                width: 1, thickness: 1, color: AppTheme.borderGlow),
          ],
          Expanded(child: _screens[_index]),
        ],
      ),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              height: 65,
              backgroundColor: AppTheme.bgSurface,
              selectedIndex: _index,
              onDestinationSelected: (idx) => setState(() => _index = idx),
              indicatorColor: AppTheme.accentCyan.withValues(alpha: 0.1),
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.bluetooth_searching), label: 'Terminal'),
                NavigationDestination(
                    icon: Icon(Icons.security), label: 'Security'),
              ],
            ),
    );
  }
}
