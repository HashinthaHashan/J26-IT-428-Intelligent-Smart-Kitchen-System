import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'clay.dart';

/// Semicircle gauge: grey groove, three round-capped segments (sage, peach,
/// coral) and a white knob that rides the arc at the current value.
class ClayGauge extends StatelessWidget {
  const ClayGauge({
    super.key,
    required this.value,
    required this.max,
    required this.knobColor,
    required this.caption,
    this.valueColor = Clay.ink,
  });

  final double value;
  final double max;
  final Color knobColor;
  final Color valueColor;

  /// Text under the number, e.g. `ppm · Normal`.
  final String caption;

  static const sageColor = Color(0xFF62B790);
  static const peachColor = Color(0xFFF9AD6C);
  static const coralColor = Color(0xFFF0777A);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = math.min(constraints.maxWidth, 320.0);
      final height = width / 2 + 34;
      return Center(
        child: SizedBox(
          width: width,
          height: height,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: value.clamp(0, max).toDouble()),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder:
                (context, shown, _) => Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _GaugePainter(
                            fraction: shown / max,
                            knobColor: knobColor,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            shown.round().toString(),
                            style: Clay.text(
                              52,
                              weight: 900,
                              color: valueColor,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            caption,
                            style: Clay.text(
                              15,
                              weight: 800,
                              color: Clay.mutedGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
          ),
        ),
      );
    },
  );
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.fraction, required this.knobColor});

  final double fraction;
  final Color knobColor;

  static const _stroke = 26.0;
  static const _segments = [
    (0.0, 0.30, ClayGauge.sageColor),
    (0.32, 0.64, ClayGauge.peachColor),
    (0.66, 0.99, ClayGauge.coralColor),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2 - 30;
    final center = Offset(size.width / 2, radius + 26);
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(
      rect,
      math.pi,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke + 12
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFE6E8DC),
    );

    // Round caps overhang by half the stroke, so inset each segment by that
    // angle to make its visible extent match its range.
    final capAngle = (_stroke / 2) / radius;
    for (final (from, to, color) in _segments) {
      canvas.drawArc(
        rect,
        math.pi + math.pi * from + capAngle,
        math.pi * (to - from) - 2 * capAngle,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _stroke
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }

    final f = fraction.isNaN ? 0.0 : fraction.clamp(0.0, 1.0);
    final angle = math.pi + math.pi * f;
    final knob = center + Offset(math.cos(angle), math.sin(angle)) * radius;
    canvas.drawCircle(
      knob + const Offset(1, 3),
      18,
      Paint()
        ..color = Clay.shadowTint.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(knob, 17, Paint()..color = Colors.white);
    canvas.drawCircle(knob, 8, Paint()..color = knobColor);
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.fraction != fraction || old.knobColor != knobColor;
}
