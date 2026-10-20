import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../models/lpg.dart';
import '../../shared/widgets/clay.dart';
import '../../shared/widgets/clay_gauge.dart';
import '../../shared/widgets/clay_layout.dart';
import '../../shared/widgets/clay_toggle.dart';
import 'lpg_providers.dart';

const _gaugeMaxPpm = 1500.0;
const _alertLimitPpm = 1000.0;
const _confirmTimeout = Duration(seconds: 12);

/// Display data derived from the backend's cloud tier.
class _Tone {
  const _Tone(this.pill, this.word, this.pillBg, this.pillFg, this.knob, this.card);
  final String pill, word;
  final Color pillBg, pillFg, knob, card;
}

_Tone _toneFor(String tier) {
  switch (tier.toLowerCase()) {
    case 'warning':
      return const _Tone('Warning', 'Elevated', Clay.warnPillBg,
          Clay.warnPillText, ClayGauge.peachColor, Clay.cardWarning);
    case 'dangerous':
      return const _Tone('Dangerous', 'High', Clay.alertPillBg,
          Clay.alertPillText, ClayGauge.coralColor, Color(0xFFFDF2EF));
    case 'critical':
      return const _Tone('Critical', 'Critical', Clay.alertPillBg,
          Clay.alertPillText, ClayGauge.coralColor, Color(0xFFFDF2EF));
    default:
      return const _Tone('Safe', 'Normal', Clay.okPillBg, Clay.okPillText,
          ClayGauge.sageColor, Clay.cardHealthy);
  }
}

class LpgScreen extends ConsumerStatefulWidget {
  const LpgScreen({super.key});

  @override
  ConsumerState<LpgScreen> createState() => _LpgScreenState();
}

/// A command that was sent and is waiting for the device to report back.
class _Pending {
  _Pending(this.target, this.timer);
  final bool target;
  final Timer timer;
}

class _LpgScreenState extends ConsumerState<LpgScreen> {
  _Pending? _fan;
  _Pending? _window;

  @override
  void dispose() {
    _fan?.timer.cancel();
    _window?.timer.cancel();
    super.dispose();
  }

  bool _fanOn(LpgSnapshot s) => s.raw.fanOn;
  bool _windowOpen(LpgSnapshot s) => s.raw.windowFrac > 0.5;

  /// Clears a pending command once telemetry shows the target state.
  void _reconcile(LpgState? state) {
    if (state == null) return;
    if (_fan != null && _fanOn(state.latest) == _fan!.target) {
      _fan!.timer.cancel();
      setState(() => _fan = null);
    }
    if (_window != null && _windowOpen(state.latest) == _window!.target) {
      _window!.timer.cancel();
      setState(() => _window = null);
    }
  }

  Future<void> _send({
    required bool fan,
    required bool target,
    required String sent,
    required String timedOut,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(lpgProvider.notifier);
    (fan ? _fan : _window)?.timer.cancel();
    final pending = _Pending(
      target,
      Timer(_confirmTimeout, () {
        if (!mounted) return;
        setState(() => fan ? _fan = null : _window = null);
        messenger.showSnackBar(SnackBar(content: Text(timedOut)));
      }),
    );
    setState(() => fan ? _fan = pending : _window = pending);
    try {
      await (fan ? notifier.setFan(target) : notifier.setWindow(target));
      messenger.showSnackBar(SnackBar(content: Text(sent)));
      if (mounted) _reconcile(ref.read(lpgProvider).value);
    } catch (error) {
      pending.timer.cancel();
      if (mounted) setState(() => fan ? _fan = null : _window = null);
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(lpgProvider, (_, next) => _reconcile(next.value));
    final value = ref.watch(lpgProvider);
    final notifier = ref.read(lpgProvider.notifier);
    const header = ClayScreenHeader(label: 'Gas monitor', title: 'LPG');

    final data = value.value;
    if (data == null) {
      return ClayPage(
        onRefresh: notifier.refresh,
        children: [
          header,
          const SizedBox(height: 22),
          value.hasError
              ? ClayMessageCard(
                message: userFacingError(value.error!),
                onRetry: notifier.refresh,
              )
              : const ClayMessageCard(message: 'Reading the gas sensor...'),
        ],
      );
    }

    final latest = data.latest;
    final tone = _toneFor(latest.prediction.cloudTier);
    final fanShown = _fan?.target ?? _fanOn(latest);
    final windowShown = _window?.target ?? _windowOpen(latest);
    return ClayPage(
      onRefresh: notifier.refresh,
      children: [
        header,
        const SizedBox(height: 22),
        if (latest.raw.edgeOfflineMode) ...[
          const _OfflineBanner(),
          const SizedBox(height: 14),
        ],
        ClayEntrance(index: 0, child: _GasCard(latest: latest, tone: tone)),
        const SizedBox(height: 28),
        const ClaySectionTitle(
          'Air quality trend',
          subtitle: 'Compensated LPG over the past 24 hours',
        ),
        const SizedBox(height: 14),
        ClayEntrance(index: 2, child: _TrendCard(history: data.history)),
        const SizedBox(height: 28),
        const ClaySectionTitle(
          'Manual controls',
          subtitle: 'Override connected ventilation devices',
        ),
        const SizedBox(height: 14),
        ClayEntrance(
          index: 3,
          child: _ControlRow(
            toggleKey: const Key('fan-toggle'),
            icon: Icons.air_rounded,
            colors: Clay.sage,
            name: 'Exhaust fan',
            status:
                _fan != null
                    ? (_fan!.target ? 'Turning on...' : 'Turning off...')
                    : (_fanOn(latest) ? 'Running' : 'Off'),
            value: fanShown,
            busy: _fan != null,
            onChanged:
                (on) => _send(
                  fan: true,
                  target: on,
                  sent: 'Exhaust fan command sent',
                  timedOut: 'The fan did not confirm. Check the device.',
                ),
          ),
        ),
        const SizedBox(height: 14),
        ClayEntrance(
          index: 4,
          child: _ControlRow(
            toggleKey: const Key('window-toggle'),
            icon: Icons.grid_view_rounded,
            colors: Clay.sky,
            name: 'Window',
            status:
                _window != null
                    ? (_window!.target ? 'Opening...' : 'Closing...')
                    : (_windowOpen(latest) ? 'Open' : 'Closed'),
            value: windowShown,
            busy: _window != null,
            onChanged:
                (open) => _send(
                  fan: false,
                  target: open,
                  sent: 'Window command sent',
                  timedOut: 'The window did not confirm. Check the device.',
                ),
          ),
        ),
        const SizedBox(height: 26),
        Center(
          child: Text(
            'Pull down to refresh',
            style: Clay.text(12, weight: 700, color: Clay.mutedWarm),
          ),
        ),
      ],
    );
  }
}

class _GasCard extends StatelessWidget {
  const _GasCard({required this.latest, required this.tone});
  final LpgSnapshot latest;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final ppm = latest.features.ppmComp;
    return ClayBox(
      radius: 34,
      color: tone.card,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      semanticLabel:
          'Current gas level ${ppm.round()} ppm, ${tone.pill}, '
          '${latest.raw.tempC.toStringAsFixed(1)} degrees, '
          '${latest.raw.rhPct.round()} percent humidity',
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current gas level',
                      style: Clay.text(19, weight: 900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Temperature and humidity compensated',
                      style: Clay.text(
                        13.5,
                        weight: 600,
                        color: Clay.mutedGreen,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ClayPill(
                label: tone.pill,
                background: tone.pillBg,
                foreground: tone.pillFg,
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClayGauge(
            value: ppm,
            max: _gaugeMaxPpm,
            knobColor: tone.knob,
            caption: 'ppm · ${tone.word}',
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _axisLabel('0'),
                _axisLabel('Alert limit ${_alertLimitPpm.round()}'),
                _axisLabel('${_gaugeMaxPpm.round()}'),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _Chip(
                  label: 'Raw',
                  value: latest.raw.ppmRaw.toStringAsFixed(0),
                  unit: 'ppm',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Chip(
                  label: 'Temperature',
                  value: latest.raw.tempC.toStringAsFixed(1),
                  unit: '°C',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Chip(
                  label: 'Humidity',
                  value: latest.raw.rhPct.toStringAsFixed(0),
                  unit: '%',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _axisLabel(String text) =>
      Text(text, style: Clay.text(12, weight: 800, color: Clay.mutedGreen));
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.value, required this.unit});
  final String label, value, unit;

  @override
  Widget build(BuildContext context) => ClayBox(
    radius: 22,
    depth: 0.5,
    color: Clay.navBar,
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
    child: Column(
      children: [
        Text(
          label,
          maxLines: 1,
          style: Clay.text(11.5, weight: 700, color: Clay.mutedWarm),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: Clay.text(18, weight: 900)),
              const SizedBox(width: 2),
              Text(
                unit,
                style: Clay.text(11.5, weight: 800, color: Clay.mutedWarm),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Peak-preserving downsample so a day of 1 Hz data stays cheap to draw.
List<LpgSnapshot> _downsample(List<LpgSnapshot> points, {int max = 160}) {
  if (points.length <= max) return points;
  final step = (points.length / max).ceil();
  final out = <LpgSnapshot>[];
  for (var i = 0; i < points.length; i += step) {
    final end = (i + step).clamp(0, points.length);
    var peak = points[i];
    for (var j = i + 1; j < end; j++) {
      if (points[j].features.ppmComp > peak.features.ppmComp) peak = points[j];
    }
    out.add(peak);
  }
  return out;
}

class _TrendCard extends StatefulWidget {
  const _TrendCard({required this.history});
  final List<LpgSnapshot> history;

  @override
  State<_TrendCard> createState() => _TrendCardState();
}

class _TrendCardState extends State<_TrendCard> {
  static const _refreshEvery = Duration(seconds: 10);
  late List<LpgSnapshot> _points = _downsample(widget.history);
  late DateTime _computedAt = DateTime.now();

  @override
  void didUpdateWidget(_TrendCard old) {
    super.didUpdateWidget(old);
    // Live frames arrive about once a second; the trend only needs to move
    // every few seconds, which keeps scrolling smooth.
    final now = DateTime.now();
    if (now.difference(_computedAt) >= _refreshEvery ||
        (_points.isEmpty && widget.history.isNotEmpty)) {
      _points = _downsample(widget.history);
      _computedAt = now;
    }
  }

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final windowStart = now.subtract(const Duration(hours: 24));
    final spots = [
      for (final p in _points)
        FlSpot(
          (p.raw.ts.difference(windowStart).inSeconds / 3600).clamp(0, 24),
          p.features.ppmComp.clamp(0, _gaugeMaxPpm),
        ),
    ];
    final labelStyle = Clay.text(11, weight: 700, color: Clay.mutedWarm);
    return ClayBox(
      radius: 30,
      color: Clay.cardWarning,
      padding: const EdgeInsets.fromLTRB(8, 22, 18, 12),
      semanticLabel: 'Air quality trend over the past 24 hours',
      child: SizedBox(
        height: 220,
        child:
            spots.length < 2
                ? Center(
                  child: Text(
                    'Collecting readings...',
                    style: Clay.text(14, weight: 700, color: Clay.mutedWarm),
                  ),
                )
                : LineChart(
                  LineChartData(
                    minX: 0,
                    maxX: 24,
                    minY: 0,
                    maxY: _gaugeMaxPpm,
                    gridData: const FlGridData(
                      drawVerticalLine: false,
                      horizontalInterval: 500,
                      getDrawingHorizontalLine: _gridLine,
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          interval: 500,
                          getTitlesWidget:
                              (v, meta) => SideTitleWidget(
                                meta: meta,
                                child: Text(
                                  switch (v.round()) {
                                    0 => '0',
                                    500 => '500',
                                    1000 => '1K',
                                    1500 => '1.5K',
                                    _ => '',
                                  },
                                  style: labelStyle,
                                ),
                              ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          interval: 6,
                          getTitlesWidget:
                              (v, meta) => SideTitleWidget(
                                meta: meta,
                                child: Text(
                                  v >= 24
                                      ? 'Now'
                                      : _clock(
                                        windowStart.add(
                                          Duration(minutes: (v * 60).round()),
                                        ),
                                      ),
                                  style: labelStyle,
                                ),
                              ),
                        ),
                      ),
                    ),
                    extraLinesData: ExtraLinesData(
                      horizontalLines: [
                        HorizontalLine(
                          y: _alertLimitPpm,
                          color: ClayGauge.coralColor,
                          strokeWidth: 1.8,
                          dashArray: [6, 5],
                        ),
                      ],
                    ),
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (_) => Clay.ink,
                        getTooltipItems:
                            (touched) => [
                              for (final t in touched)
                                LineTooltipItem(
                                  '${t.y.round()} ppm\n'
                                  '${_clock(windowStart.add(Duration(minutes: (t.x * 60).round())))}',
                                  Clay.text(
                                    12.5,
                                    weight: 800,
                                    color: Colors.white,
                                  ),
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
                ),
      ),
    );
  }
}

FlLine _gridLine(double _) =>
    const FlLine(color: Color(0xFFEBE2D3), strokeWidth: 1.2);

class _ControlRow extends StatelessWidget {
  const _ControlRow({
    required this.toggleKey,
    required this.icon,
    required this.colors,
    required this.name,
    required this.status,
    required this.value,
    required this.busy,
    required this.onChanged,
  });

  final Key toggleKey;
  final IconData icon;
  final List<Color> colors;
  final String name, status;
  final bool value, busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => ClayBox(
    radius: 28,
    color: Clay.cardHealthy,
    padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
    child: Row(
      children: [
        ClayIconBlob(icon: icon, colors: colors, size: 50),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: Clay.text(17, weight: 800)),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  status,
                  key: ValueKey(status),
                  style: Clay.text(
                    14,
                    weight: 700,
                    color: busy ? Clay.warnPillText : Clay.mutedGreen,
                  ),
                ),
              ),
            ],
          ),
        ),
        ClayToggle(
          key: toggleKey,
          value: value,
          busy: busy,
          semanticLabel: '$name, $status',
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) => ClayBox(
    radius: 24,
    color: const Color(0xFFFFF1D9),
    padding: const EdgeInsets.all(16),
    semanticLabel: 'Device acting independently, no cloud connection',
    child: Row(
      children: [
        const Icon(Icons.cloud_off_rounded, color: Clay.warnPillText),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Device acting independently - no cloud connection',
            style: Clay.text(13.5, weight: 700, color: Clay.warnPillText),
          ),
        ),
      ],
    ),
  );
}
