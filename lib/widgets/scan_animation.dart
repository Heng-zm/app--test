import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ScanAnimation extends StatefulWidget {
  final double size;

  const ScanAnimation({super.key, required this.size});

  @override
  State<ScanAnimation> createState() => _ScanAnimationState();
}

class _ScanAnimationState extends State<ScanAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (_, __) {
              return CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _ScanPainter(_controller.value),
              );
            },
          ),
          Icon(
            Icons.bluetooth,
            color: AppTheme.accentCyan,
            size: widget.size * 0.35,
          ),
        ],
      ),
    );
  }
}

class _ScanPainter extends CustomPainter {
  final double progress;

  _ScanPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    for (int i = 0; i < 3; i++) {
      final waveProgress = (progress + i * 0.33) % 1.0;
      final radius = waveProgress * maxRadius;
      final opacity = (1.0 - waveProgress) * 0.5;

      final paint = Paint()
        ..color = AppTheme.accentCyan.withOpacity(opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      canvas.drawCircle(center, radius, paint);
    }

    // Inner static ring
    final staticPaint = Paint()
      ..color = AppTheme.accentCyan.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, maxRadius * 0.4, staticPaint);
  }

  @override
  bool shouldRepaint(_ScanPainter old) => old.progress != progress;
}
