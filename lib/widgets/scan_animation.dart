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
    return RepaintBoundary(
      // 🟢 PERF: Isolate animation from the rest of the UI tree
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) =>
              CustomPaint(painter: _RadarPainter(_controller.value)),
        ),
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

    // 1. Draw Background Grid (Fixed)
    final gridPaint = Paint()
      ..color = AppTheme.accentCyan.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawCircle(center, radius * 0.4, gridPaint);
    canvas.drawCircle(center, radius * 0.7, gridPaint);
    canvas.drawCircle(center, radius, gridPaint);

    // 2. Draw Pulsing Waves
    for (int i = 0; i < 2; i++) {
      final waveProgress = (progress + (i * 0.5)) % 1.0;
      final wavePaint = Paint()
        ..color =
            AppTheme.accentCyan.withValues(alpha: (1.0 - waveProgress) * 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawCircle(center, waveProgress * radius, wavePaint);
    }

    // 3. Draw Rotating Sweep Beam
    // 🟢 PERF: Use a more focused sweep angle for a "high-tech" look
    final Rect rect = Rect.fromCircle(center: center, radius: radius);
    final Shader sweepShader = SweepGradient(
      colors: [
        AppTheme.accentCyan.withValues(alpha: 0.0),
        AppTheme.accentCyan.withValues(alpha: 0.5),
        AppTheme.accentCyan.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.5, 1.0],
      transform: GradientRotation(progress * math.pi * 2 - (math.pi / 2)),
    ).createShader(rect);

    final Paint sweepPaint = Paint()
      ..shader = sweepShader
      ..style = PaintingStyle.fill;

    // Draw the actual scanning beam
    canvas.drawArc(rect, progress * math.pi * 2 - 1.0, 1.0, true, sweepPaint);

    // 4. Draw Leading Edge (The bright tip of the radar)
    final double tipAngle = progress * math.pi * 2;
    final tipPaint = Paint()
      ..color = AppTheme.accentCyan
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;

    canvas.drawLine(
      center,
      Offset(
        center.dx + math.cos(tipAngle) * radius,
        center.dy + math.sin(tipAngle) * radius,
      ),
      tipPaint,
    );
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.progress != progress;
}
