import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';

class FreshnessBar extends StatelessWidget {
  const FreshnessBar({super.key, required this.score, required this.stage});

  final double score;
  final String stage;

  @override
  Widget build(BuildContext context) {
    final value = score.clamp(0, 100).toDouble();
    return Semantics(
      label: '${value.round()} percent fresh, $stage',
      child: SizedBox(
        height: 76,
        child: Stack(
          alignment: Alignment.center,
          children: [
            RotatedBox(
              quarterTurns: 1,
              child: BarChart(
                BarChartData(
                  maxY: 100,
                  minY: 0,
                  alignment: BarChartAlignment.center,
                  gridData: const FlGridData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  barTouchData: BarTouchData(enabled: false),
                  barGroups: [
                    BarChartGroupData(
                      x: 0,
                      barRods: [
                        BarChartRodData(
                          toY: value,
                          width: 38,
                          borderRadius: BorderRadius.circular(8),
                          color: statusColor(stage),
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: 100,
                            color: softSurface,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Text(
              '${value.round()}%',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      ),
    );
  }
}
