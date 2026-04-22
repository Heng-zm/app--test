import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class BTSignalBars extends StatelessWidget {
  final int bars; // 1–4

  const BTSignalBars({super.key, required this.bars});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (index) {
        final isActive = index < bars;
        return Container(
          width: 3,
          height: 4.0 + (index * 2.5),
          margin: const EdgeInsets.only(right: 1.5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(1),
            color: isActive
                ? (bars >= 3
                    ? AppTheme.accentGreen
                    : bars == 2
                        ? AppTheme.warning
                        : AppTheme.danger)
                : AppTheme.textDim,
          ),
        );
      }),
    );
  }
}
