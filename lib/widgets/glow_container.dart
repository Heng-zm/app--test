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
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: (glowColor ?? AppTheme.accentCyan).withOpacity(0.15),
            blurRadius: blurRadius,
            spreadRadius: 0,
          ),
        ],
      ),
      child: child,
    );
  }
}
