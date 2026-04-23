import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class BTSignalBars extends StatelessWidget {
  final int bars; // 0–4

  const BTSignalBars({super.key, required this.bars});

  @override
  Widget build(BuildContext context) {
    // Determine the color once for efficiency
    final Color activeColor = _getSignalColor();

    return Semantics(
      label: 'Signal strength: $bars out of 4 bars',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(4, (index) {
          final isActive = index < bars;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            width: 3,
            height: 4.0 + (index * 2.5), // 4.0, 6.5, 9.0, 11.5
            margin: const EdgeInsets.only(right: 1.5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(1),
              color: isActive ? activeColor : AppTheme.textDim.withOpacity(0.2),
              boxShadow: [
                if (isActive)
                  BoxShadow(
                    color: activeColor.withOpacity(0.3),
                    blurRadius: 2,
                    spreadRadius: 0.5,
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Color _getSignalColor() {
    if (bars >= 3) return AppTheme.accentGreen;
    if (bars == 2) return AppTheme.warning;
    if (bars == 1) return AppTheme.danger;
    return AppTheme.textDim;
  }
}
