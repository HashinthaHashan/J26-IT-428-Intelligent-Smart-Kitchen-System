import 'package:flutter/material.dart';

import 'clay.dart';

/// Sunken track with a violet clay pill that slides under the selected label.
class ClaySegmented extends StatelessWidget {
  const ClaySegmented({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  static const _height = 56.0;
  static const _inset = 5.0;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFFEFE7D9),
      borderRadius: BorderRadius.circular(28),
      // The track sits lower than the page: a soft light edge along the bottom.
      boxShadow: [
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.7),
          offset: const Offset(0, 3),
          blurRadius: 6,
        ),
      ],
    ),
    foregroundDecoration: BoxDecoration(
      borderRadius: BorderRadius.circular(28),
      // Inner shadow along the top edge.
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0, 0.35],
        colors: [
          Clay.shadowTint.withValues(alpha: 0.22),
          Colors.transparent,
        ],
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.all(_inset),
      child: SizedBox(
        height: _height - 2 * _inset,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth / labels.length;
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutBack,
                  left: width * selected,
                  top: 0,
                  width: width,
                  height: constraints.maxHeight,
                  child: ClayBox(
                    radius: 24,
                    depth: 0.55,
                    gradient: clayGradient(Clay.violet),
                    child: const SizedBox.expand(),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < labels.length; i++)
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: i == selected,
                          label: labels[i],
                          excludeSemantics: true,
                          onTap: () => onChanged(i),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => onChanged(i),
                            child: Center(
                              child: AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 220),
                                style: Clay.text(
                                  16,
                                  weight: 900,
                                  color:
                                      i == selected
                                          ? Colors.white
                                          : Clay.mutedWarm,
                                ),
                                child: Text(labels[i]),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
