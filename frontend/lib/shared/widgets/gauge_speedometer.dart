import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

class GaugeSpeedometer extends StatelessWidget {
  const GaugeSpeedometer({
    super.key,
    required this.value,
    required this.status,
  });

  final double value;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${value.round()} parts per million, $status',
      child: SizedBox(
        height: 190,
        width: double.infinity,
        child: CustomPaint(
          painter: _GaugePainter(value: value.clamp(0, 1500).toDouble()),
          child: Align(
            alignment: const Alignment(0, 0.52),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value.toStringAsFixed(0),
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: statusColor(status),
                  ),
                ),
                Text('ppm', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter({required this.value});
  final double value;

  static const _start = math.pi * 0.78;
  static const _sweep = math.pi * 1.44;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.78);
    final radius = math.min(size.width * 0.4, size.height * 0.68);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 13
          ..strokeCap = StrokeCap.round;
    final bands = <(double, Color)>[
      (150 / 1500, safeGreen),
      (150 / 1500, warningAmber),
      (400 / 1500, dangerousOrange),
      (800 / 1500, criticalRed),
    ];
    var angle = _start;
    for (final band in bands) {
      final sweep = _sweep * band.$1;
      paint.color = band.$2;
      canvas.drawArc(rect, angle, sweep - 0.015, false, paint);
      angle += sweep;
    }
    final needleAngle = _start + _sweep * (value / 1500);
    final needleEnd =
        center +
        Offset(math.cos(needleAngle), math.sin(needleAngle)) * (radius - 20);
    canvas.drawLine(
      center,
      needleEnd,
      Paint()
        ..color = ink
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(center, 6, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.value != value;
}
