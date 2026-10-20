import 'dart:async';

import 'package:flutter/material.dart';

class ShelfLifeCountdown extends StatefulWidget {
  const ShelfLifeCountdown({
    super.key,
    required this.hoursAtReading,
    required this.readingTime,
  });

  final double hoursAtReading;
  final DateTime readingTime;

  @override
  State<ShelfLifeCountdown> createState() => _ShelfLifeCountdownState();
}

class _ShelfLifeCountdownState extends State<ShelfLifeCountdown> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(widget.readingTime).inSeconds;
    final seconds =
        (widget.hoursAtReading * 3600 - elapsed)
            .clamp(0, double.infinity)
            .round();
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final label =
        days > 0
            ? '${days}d ${hours}h'
            : hours > 0
            ? '${hours}h ${minutes}m'
            : '${minutes}m';
    return Semantics(
      label: 'Remaining shelf life $label',
      child: Text(label, style: Theme.of(context).textTheme.displaySmall),
    );
  }
}
