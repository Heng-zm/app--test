import 'package:flutter/material.dart';
import '../platform/app_platform.dart';
import '../theme/app_theme.dart';

/// A small, stylized badge that identifies the current operating system.
/// Matches the app's technical/cyberpunk aesthetic.
class PlatformBadge extends StatelessWidget {
  const PlatformBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final Color platformColor = _getPlatformColor();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        // Subtle background glow using the platform's signature color
        color: platformColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: platformColor.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Text(
        AppPlatform.name.toUpperCase(),
        style: TextStyle(
          color: platformColor,
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  /// Maps the platform to a specific color from the AppTheme.
  Color _getPlatformColor() {
    if (AppPlatform.isAndroid) return AppTheme.accentGreen;
    if (AppPlatform.isIOS) return AppTheme.accentCyan;
    if (AppPlatform.isMacOS) return AppTheme.accentPurple;
    if (AppPlatform.isWindows) return const Color(0xFF0078D4); // Windows Blue
    if (AppPlatform.isLinux) return AppTheme.accentTeal;
    if (AppPlatform.isWeb) return Colors.orangeAccent;
    if (AppPlatform.isFuchsia) return Colors.pinkAccent;

    return AppTheme.textDim;
  }
}
