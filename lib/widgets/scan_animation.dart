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
      duration: const Duration(
          seconds: 3), // Slightly slower for a more "scanning" feel
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
          // The Animated Radar
          AnimatedBuilder(
            animation: _controller,
            builder: (_, __) {
              return CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _RadarPainter(_controller.value),
              );
            },
          ),
          // Center Icon with a soft pulse
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.8, end: 1.1),
            duration: const Duration(seconds: 1),
            curve: Curves.easeInOut,
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: Icon(
                  Icons.bluetooth,
                  color: AppTheme.accentCyan,
                  size: widget.size * 0.3,
                ),
              );
            },
          ),
        ],
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

    // 1. Draw Background Circles (Grid)
    final gridPaint = Paint()
      ..color = AppTheme.accentCyan.withOpacity(0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawCircle(center, radius * 0.4, gridPaint);
    canvas.drawCircle(center, radius * 0.7, gridPaint);
    canvas.drawCircle(center, radius, gridPaint);

    // 2. Draw Expanding Waves
    for (int i = 0; i < 2; i++) {
      final waveProgress = (progress + (i * 0.5)) % 1.0;
      final waveRadius = waveProgress * radius;
      final waveOpacity = (1.0 - waveProgress) * 0.3;

      final wavePaint = Paint()
        ..color = AppTheme.accentCyan.withOpacity(waveOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawCircle(center, waveRadius, wavePaint);
    }

    // 1. Create the SHADER (the "ink")
    final radarShader = SweepGradient(
      center: Alignment.center,
      startAngle: 0.0,
      endAngle: pi * 2,
      colors: [
        AppTheme.accentCyan.withOpacity(0.0),
        AppTheme.accentCyan.withOpacity(0.4),
        AppTheme.accentCyan.withOpacity(0.0),
      ],
      stops: const [0.0, 0.2, 0.25],
      transform: GradientRotation(progress * pi * 2),
    ).createShader(Rect.fromCircle(center: center, radius: radius));

// 2. Draw using a Paint object with that shader assigned
    canvas.drawCircle(
        center, radius, Paint()..shader = radarShader // Works now!
        );

    // 4. Draw Compass Ticks (Outer Border)
    final tickPaint = Paint()
      ..color = AppTheme.accentCyan.withOpacity(0.3)
      ..strokeWidth = 1.5;

    for (int i = 0; i < 36; i++) {
      final angle = (i * 10) * pi / 180;
      final isLongTick = i % 9 == 0;
      final tickLength = isLongTick ? 8.0 : 4.0;

      final start = Offset(
        center.dx + (radius - 2) * cos(angle),
        center.dy + (radius - 2) * sin(angle),
      );
      final end = Offset(
        center.dx + (radius - 2 - tickLength) * cos(angle),
        center.dy + (radius - 2 - tickLength) * sin(angle),
      );
      canvas.drawLine(start, end, tickPaint);
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.progress != progress;
}
