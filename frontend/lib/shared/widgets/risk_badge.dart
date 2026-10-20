import 'package:flutter/material.dart';

import '../../core/theme.dart';

class RiskBadge extends StatefulWidget {
  const RiskBadge({super.key, required this.status, this.large = false});

  final String status;
  final bool large;

  @override
  State<RiskBadge> createState() => _RiskBadgeState();
}

class _RiskBadgeState extends State<RiskBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
      lowerBound: 0.82,
      upperBound: 1,
    )..value = 1;
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant RiskBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.large && widget.status.toLowerCase() == 'danger') {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = statusColor(widget.status);
    return FadeTransition(
      opacity: _controller,
      child: Semantics(
        label: 'Status ${widget.status}',
        child: Container(
          key: ValueKey('risk-badge-${widget.status}'),
          padding: EdgeInsets.symmetric(
            horizontal: widget.large ? 18 : 9,
            vertical: widget.large ? 9 : 5,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            border: Border.all(color: color),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            widget.status,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: widget.large ? 20 : 12,
            ),
          ),
        ),
      ),
    );
  }
}
