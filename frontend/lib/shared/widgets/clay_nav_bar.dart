import 'package:flutter/material.dart';

import 'clay.dart';

class ClayNavItem {
  const ClayNavItem(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Floating pill navigation with a violet clay indicator that slides to the
/// selected tab. It has no backing strip: it floats over the screen.
class ClayNavBar extends StatelessWidget {
  const ClayNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<ClayNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _inset = 6.0;
  static const _tabHeight = 58.0;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Clay.maxContentWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 4, 28, 14),
          child: ClayBox(
            radius: 32,
            color: Clay.navBar,
            padding: const EdgeInsets.all(_inset),
            child: SizedBox(
              height: _tabHeight,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final tabWidth = constraints.maxWidth / items.length;
                  return Stack(
                    children: [
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 380),
                        curve: Curves.easeOutBack,
                        left: tabWidth * selectedIndex,
                        top: 0,
                        width: tabWidth,
                        height: _tabHeight,
                        child: ClayBox(
                          radius: 26,
                          depth: 0.55,
                          gradient: clayGradient(Clay.violet),
                          child: const SizedBox.expand(),
                        ),
                      ),
                      Row(
                        children: [
                          for (var i = 0; i < items.length; i++)
                            Expanded(
                              child: _NavTab(
                                item: items[i],
                                selected: i == selectedIndex,
                                onTap: () => onSelected(i),
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
        ),
      ),
    ),
  );
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final ClayNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: item.label,
    excludeSemantics: true,
    onTap: onTap,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(26),
      child: SizedBox(
        height: ClayNavBar._tabHeight,
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: selected ? Colors.white : Clay.mutedWarm),
          duration: const Duration(milliseconds: 250),
          builder: (context, color, _) {
            final c = color ?? Clay.mutedWarm;
            return AnimatedScale(
              scale: selected ? 1.06 : 1,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutBack,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(item.icon, color: c, size: 23),
                  const SizedBox(height: 3),
                  Text(
                    item.label,
                    maxLines: 1,
                    style: Clay.text(
                      11.5,
                      weight: selected ? 900 : 800,
                      color: c,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}
