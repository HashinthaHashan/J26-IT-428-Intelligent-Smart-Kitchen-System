import 'package:flutter/material.dart';

/// Claymorphism tokens and primitives used by the Home screen and bottom nav.
/// Other screens keep the calm theme in `core/theme.dart`.
class Clay {
  const Clay._();

  static const background = Color(0xFFF6F0E7);
  static const cardWarning = Color(0xFFFBF8F1);
  static const cardHealthy = Color(0xFFF3F8EF);
  static const navBar = Color(0xFFFBF7F0);
  static const ink = Color(0xFF2B2745);
  static const mutedWarm = Color(0xFF8A8498);
  static const mutedGreen = Color(0xFF6C7D70);
  static const badge = Color(0xFFF0586B);
  static const shadowTint = Color(0xFF8A6A48);

  static const violet = [Color(0xFF9A9DF5), Color(0xFF5D5FD6)];
  static const peach = [Color(0xFFFFCC99), Color(0xFFF79A56)];
  static const coral = [Color(0xFFFFC2BD), Color(0xFFF0777A)];
  static const sage = [Color(0xFFB3E3C6), Color(0xFF62B790)];
  static const sky = [Color(0xFFB8D8FF), Color(0xFF6A9CF0)];

  static const warnPillBg = Color(0xFFFFE9BF);
  static const warnPillText = Color(0xFF8A5200);
  static const alertPillBg = Color(0xFFFFDAD6);
  static const alertPillText = Color(0xFF9B2C35);
  static const okPillBg = Color(0xFFDFF0E3);
  static const okPillText = Color(0xFF2C7357);
  static const neutralPillBg = Color(0xFFEAE5DC);
  static const neutralPillText = Color(0xFF6A6478);

  static const maxContentWidth = 430.0;
  static const screenPadding = 20.0;

  /// Nunito text style. The variable font needs the explicit `wght` axis.
  static TextStyle text(
    double size, {
    int weight = 700,
    Color color = ink,
    double? height,
  }) => TextStyle(
    fontFamily: 'Nunito',
    fontSize: size,
    height: height,
    color: color,
    fontWeight: FontWeight.values[(weight ~/ 100) - 1],
    fontVariations: [FontVariation('wght', weight.toDouble())],
  );
}

LinearGradient clayGradient(List<Color> colors) => LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: colors,
);

/// A puffy surface: outer drop shadow, outer white highlight, plus an inner
/// top highlight and inner bottom tint (Flutter has no inset shadows, so the
/// inner pair is drawn as a gradient overlay). Tappable surfaces squish
/// slightly while pressed.
class ClayBox extends StatefulWidget {
  const ClayBox({
    super.key,
    required this.child,
    this.radius = 30,
    this.color,
    this.gradient,
    this.padding,
    this.onTap,
    this.semanticLabel,
    this.depth = 1,
  });

  final Widget child;
  final double radius;
  final Color? color;
  final Gradient? gradient;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final String? semanticLabel;

  /// Scales shadow size; small elements use less than 1.
  final double depth;

  @override
  State<ClayBox> createState() => _ClayBoxState();
}

class _ClayBoxState extends State<ClayBox> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(widget.radius);
    final depth = widget.depth;
    final dark = widget.gradient != null;
    // The overlay carries the same radius as the surface, so no ClipRRect
    // (an extra clip layer per card was a scroll-jank source).
    Widget body = DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.035, 0.88, 1],
          colors: [
            Colors.white.withValues(alpha: dark ? 0.22 : 0.28),
            Colors.white.withValues(alpha: 0),
            Clay.shadowTint.withValues(alpha: 0),
            (dark ? const Color(0xFF2A2B8A) : Clay.shadowTint).withValues(
              alpha: 0.12,
            ),
          ],
        ),
      ),
      child: Padding(
        padding: widget.padding ?? EdgeInsets.zero,
        child: widget.child,
      ),
    );
    if (widget.onTap != null) {
      body = Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (down) => setState(() => _pressed = down),
          borderRadius: borderRadius,
          splashColor: Colors.white.withValues(alpha: 0.25),
          highlightColor: Colors.white.withValues(alpha: 0.12),
          child: body,
        ),
      );
    }
    Widget box = DecoratedBox(
      decoration: BoxDecoration(
        color: widget.gradient == null ? (widget.color ?? Clay.cardWarning) : null,
        gradient: widget.gradient,
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Clay.shadowTint.withValues(alpha: 0.25),
            offset: Offset(8 * depth, 10 * depth),
            blurRadius: 20 * depth,
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.55),
            offset: Offset(-5 * depth, -5 * depth),
            blurRadius: 16 * depth,
          ),
        ],
      ),
      child: body,
    );
    if (widget.onTap != null) {
      box = AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: box,
      );
    }
    // Each clay surface paints (and blurs its shadows) once, then is reused
    // while scrolling.
    box = RepaintBoundary(child: box);
    if (widget.semanticLabel == null) return box;
    return Semantics(
      button: widget.onTap != null,
      label: widget.semanticLabel,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: box,
    );
  }
}

/// Glossy colored icon blob.
class ClayIconBlob extends StatelessWidget {
  const ClayIconBlob({
    super.key,
    required this.icon,
    required this.colors,
    this.size = 52,
    this.radius = 18,
    this.iconColor = Colors.white,
  });

  final IconData icon;
  final List<Color> colors;
  final double size;
  final double radius;
  final Color iconColor;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: size,
      height: size,
      child: ClayBox(
        radius: radius,
        depth: 0.5,
        gradient: clayGradient(colors),
        child: Center(child: Icon(icon, color: iconColor, size: size * 0.46)),
      ),
    ),
  );
}

/// Status pill: always a word, never color alone.
class ClayPill extends StatelessWidget {
  const ClayPill({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.fontSize = 12.5,
  });

  final String label;
  final Color background;
  final Color foreground;
  final double fontSize;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(999),
      boxShadow: [
        BoxShadow(
          color: Clay.shadowTint.withValues(alpha: 0.14),
          offset: const Offset(2, 3),
          blurRadius: 6,
        ),
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.45),
          offset: const Offset(-2, -2),
          blurRadius: 5,
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Text(
        label,
        maxLines: 1,
        style: Clay.text(fontSize, weight: 800, color: foreground),
      ),
    ),
  );
}

/// Inset groove with a gradient fill.
class ClayProgress extends StatelessWidget {
  const ClayProgress({
    super.key,
    required this.value,
    required this.colors,
    this.height = 12,
  });

  /// 0..1
  final double value;
  final List<Color> colors;
  final double height;

  @override
  Widget build(BuildContext context) {
    final fraction = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    final radius = BorderRadius.circular(height);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: fraction),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, shown, _) => _groove(fraction, shown, radius),
    );
  }

  Widget _groove(double fraction, double shown, BorderRadius radius) {
    return Semantics(
      label: '${(fraction * 100).round()} percent',
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: const Color(0xFFEBE2D3),
            border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              children: [
                FractionallySizedBox(
                  widthFactor: shown,
                  heightFactor: 1,
                  alignment: Alignment.centerLeft,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      gradient: LinearGradient(colors: colors),
                    ),
                  ),
                ),
                // Inner shadow cast from the top edge of the groove.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0, 0.55],
                        colors: [
                          Clay.shadowTint.withValues(alpha: 0.28),
                          Clay.shadowTint.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
