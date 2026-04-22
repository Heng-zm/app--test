import 'package:flutter/material.dart';
import '../platform/app_platform.dart';
import '../theme/app_theme.dart';

class PlatformBadge extends StatelessWidget {
  const PlatformBadge({super.key});

  @override
  Widget build(BuildContext context) {
    Color color;
    if (AppPlatform.isAndroid)       color = AppTheme.accentGreen;
    else if (AppPlatform.isIOS)      color = AppTheme.accentCyan;
    else if (AppPlatform.isMacOS)    color = AppTheme.accentPurple;
    else if (AppPlatform.isWindows)  color = const Color(0xFF0078D4);
    else if (AppPlatform.isLinux)    color = AppTheme.accentTeal;
    else                             color = AppTheme.textDim;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        AppPlatform.name.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
