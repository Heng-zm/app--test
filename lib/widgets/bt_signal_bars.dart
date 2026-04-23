import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class BTSignalBars extends StatelessWidget {
  final int bars;
  const BTSignalBars({super.key, required this.bars});

  @override
  Widget build(BuildContext context) {
    final activeColor = bars >= 3
        ? AppTheme.accentGreen
        : bars == 2
            ? AppTheme.warning
            : AppTheme.danger;

    return Semantics(
      label: 'Signal strength $bars of 4',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(4, (index) {
          final isActive = index < bars;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            width: 3,
            height: 4.0 + (index * 2.5),
            margin: const EdgeInsets.only(right: 1.5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(1),
              color: isActive
                  ? activeColor
                  : AppTheme.textDim.withValues(alpha: 0.2),
              boxShadow: [
                if (isActive)
                  BoxShadow(
                      color: activeColor.withValues(alpha: 0.3),
                      blurRadius: 2,
                      spreadRadius: 0.5),
              ],
            ),
          );
        }),
      ),
    );
  }
}
