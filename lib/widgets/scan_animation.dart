import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'dart:math' as math;

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
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 3))
          ..repeat();
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
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) =>
            CustomPaint(painter: _RadarPainter(_controller.value)),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double progress;
  _RadarPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final gridPaint = Paint()
      ..color = AppTheme.accentCyan.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius * 0.7, gridPaint);

    for (int i = 0; i < 2; i++) {
      final waveProgress = (progress + (i * 0.5)) % 1.0;
      final wavePaint = Paint()
        ..color =
            AppTheme.accentCyan.withValues(alpha: (1.0 - waveProgress) * 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, waveProgress * radius, wavePaint);
    }

    final Shader sweepShader = SweepGradient(
      colors: [
        AppTheme.accentCyan.withValues(alpha: 0.0),
        AppTheme.accentCyan.withValues(alpha: 0.4),
        AppTheme.accentCyan.withValues(alpha: 0.0)
      ],
      stops: const [0.0, 0.2, 0.25],
      transform: GradientRotation(progress * math.pi * 2),
    ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, Paint()..shader = sweepShader);
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.progress != progress;
}
