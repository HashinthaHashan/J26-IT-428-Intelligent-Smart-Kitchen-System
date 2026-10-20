import 'package:flutter/material.dart';

import 'clay.dart';

/// Clay switch: violet gradient when on, beige groove when off, white knob.
/// While [busy] the knob shows a spinner (a command is waiting for the
/// device to confirm) and taps are ignored.
class ClayToggle extends StatelessWidget {
  const ClayToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.busy = false,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool busy;
  final String? semanticLabel;

  static const _width = 62.0;
  static const _height = 34.0;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null && !busy;
    void toggle() => onChanged!(!value);
    return Semantics(
      toggled: value,
      enabled: enabled,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: enabled ? toggle : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? toggle : null,
        // 62x48 hit area; the visible track is 34 tall.
        child: SizedBox(
          width: _width,
          height: 48,
          child: Center(
            child: RepaintBoundary(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                width: _width,
                height: _height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_height),
                  color: value ? null : const Color(0xFFD9D3C6),
                  gradient: value ? clayGradient(Clay.violet) : null,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.5),
                      offset: const Offset(0, 2),
                      blurRadius: 4,
                    ),
                  ],
                ),
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_height),
                  // Inner shadow along the top of the groove.
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, 0.55],
                    colors: [
                      (value ? const Color(0xFF2A2B8A) : Clay.shadowTint)
                          .withValues(alpha: value ? 0.30 : 0.22),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  alignment:
                      value ? Alignment.centerRight : Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Clay.shadowTint.withValues(alpha: 0.35),
                            offset: const Offset(1, 3),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child:
                          busy
                              ? Padding(
                                padding: const EdgeInsets.all(6),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Clay.violet.last,
                                ),
                              )
                              : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
