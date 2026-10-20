import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'clay.dart';

/// A violet line chart over the last [window], with real clock times on the
/// x-axis and an auto-fitted y-axis. [points] must be oldest first.
class ClayLineChart extends StatelessWidget {
  const ClayLineChart({
    super.key,
    required this.points,
    required this.unit,
    this.window = const Duration(hours: 24),
    this.decimals = 1,
  });

  final List<(DateTime, double)> points;
  final String unit;
  final Duration window;
  final int decimals;

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Peak-preserving downsample so a day of per-minute data stays cheap.
  static List<(DateTime, double)> downsample(
    List<(DateTime, double)> pts, {
    int max = 160,
  }) {
    if (pts.length <= max) return pts;
    final step = (pts.length / max).ceil();
    final out = <(DateTime, double)>[];
    for (var i = 0; i < pts.length; i += step) {
      final end = (i + step).clamp(0, pts.length);
      var peak = pts[i];
      for (var j = i + 1; j < end; j++) {
        if (pts[j].$2 > peak.$2) peak = pts[j];
      }
      out.add(peak);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = now.subtract(window);
    final hours = window.inMinutes / 60;
    final shown = downsample(points);
    final spots = [
      for (final p in shown)
        FlSpot(
          (p.$1.toLocal().difference(start).inSeconds / 3600).clamp(0, hours),
          p.$2,
        ),
    ];
    if (spots.length < 2) {
      return Center(
        child: Text(
          'Collecting readings...',
          style: Clay.text(14, weight: 700, color: Clay.mutedWarm),
        ),
      );
    }
    var lo = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    var hi = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    if (hi - lo < 1e-6) {
      lo -= 1;
      hi += 1;
    }
    final pad = (hi - lo) * 0.15;
    final minY = lo - pad, maxY = hi + pad;
    final labelStyle = Clay.text(11, weight: 700, color: Clay.mutedWarm);
    final tickEvery = hours / 4;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: hours,
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: (maxY - minY) / 3,
          getDrawingHorizontalLine:
              (_) => const FlLine(color: Color(0xFFEBE2D3), strokeWidth: 1.2),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: (maxY - minY) / 3,
              getTitlesWidget:
                  (v, meta) => SideTitleWidget(
                    meta: meta,
                    child: Text(v.toStringAsFixed(decimals), style: labelStyle),
                  ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: tickEvery,
              getTitlesWidget:
                  (v, meta) => SideTitleWidget(
                    meta: meta,
                    child: Text(
                      v >= hours - 0.01
                          ? 'Now'
                          : _clock(
                            start.add(Duration(minutes: (v * 60).round())),
                          ),
                      style: labelStyle,
                    ),
                  ),
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => Clay.ink,
            getTooltipItems:
                (touched) => [
                  for (final t in touched)
                    LineTooltipItem(
                      '${t.y.toStringAsFixed(decimals)} $unit\n'
                      '${_clock(start.add(Duration(minutes: (t.x * 60).round())))}',
                      Clay.text(12.5, weight: 800, color: Colors.white),
                    ),
                ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            preventCurveOverShooting: true,
            barWidth: 3.5,
            isStrokeCapRound: true,
            gradient: clayGradient(Clay.violet),
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Clay.violet.last.withValues(alpha: 0.28),
                  Clay.violet.last.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
