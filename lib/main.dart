import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'models/message_model.dart';
import 'platform/app_platform.dart';
import 'services/bluetooth_service.dart';
import 'screens/home_screen.dart';
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
        // Responsive breakpoint: show sidebar on wide screens
        builder: (context, child) {
          return MediaQuery(
            // Clamp text scale so layout never breaks on accessibility sizes
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(
                MediaQuery.of(context).textScaler.scale(1.0).clamp(0.8, 1.3),
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

/// Top-level shell: uses a NavigationRail on wide screens (desktop/tablet),
/// bottom nav on narrow screens (phone).
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _screens = [HomeScreen(), HomeScreen()]; // extended later

  @override
  Widget build(BuildContext context) {
    return const HomeScreen();
  }
}
