import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class GlowContainer extends StatelessWidget {
  final Widget child;
  final Color? glowColor;
  final double blurRadius;

  const GlowContainer({
    super.key,
    required this.child,
    this.glowColor,
    this.blurRadius = 12,
  });

  @override
  Widget build(BuildContext context) {
    // 🛠️ PERF: Resolve the effective color once before rendering the shadow
    final effectiveColor = glowColor ?? AppTheme.accentCyan;

    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            // 🛠️ FIX: Replaced deprecated .withOpacity with .withValues for Flutter 3.27+
            color: effectiveColor.withValues(alpha: 0.15),
            blurRadius: blurRadius,
            spreadRadius: 0,
          ),
        ],
      ),
      child: child,
    );
  }
}
