import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class BTSignalBars extends StatelessWidget {
  final int bars;

  const BTSignalBars({
    super.key,
    required this.bars,
  });

  @override
  Widget build(BuildContext context) {
    // 🟢 FIX: Clamp value to prevent indexing errors or layout overflows
    final int displayBars = bars.clamp(0, 4);

    final Color activeColor = displayBars >= 3
        ? AppTheme.accentGreen
        : displayBars == 2
            ? AppTheme.warning
            : AppTheme.danger;

    return Semantics(
      label: 'Signal strength: $displayBars out of 4 bars',
      value: '$displayBars',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(4, (index) {
          final bool isActive = index < displayBars;

          return AnimatedContainer(
            // 🟢 PERF: Snappier duration reduces "laggy" feeling during rapid RSSI updates
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            width: 3.5,
            height: 4.0 + (index * 3.0),
            margin: const EdgeInsets.only(right: 2.0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(1),
              color: isActive
                  ? activeColor
                  : AppTheme.textDim.withValues(alpha: 0.15),
              // 🟢 PERF: Simplified shadow logic to reduce GPU overdraw in long lists
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: activeColor.withValues(alpha: 0.2),
                        blurRadius: 2,
                      ),
                    ]
                  : null,
            ),
          );
        }),
      ),
    );
  }
}
