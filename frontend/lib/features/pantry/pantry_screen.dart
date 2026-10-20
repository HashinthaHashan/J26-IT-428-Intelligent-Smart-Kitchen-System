import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../models/pantry.dart';
import '../../shared/widgets/clay.dart';
import '../../shared/widgets/clay_layout.dart';
import '../../shared/widgets/clay_line_chart.dart';
import '../../shared/widgets/clay_segmented.dart';
import 'pantry_providers.dart';
import 'pantry_view.dart';

const _crops = ['banana', 'potato'];
const _lightViolet = [Color(0xFFC9CBFA), Color(0xFF8E91EC)];
// A reading older than this is flagged: the sensor board publishes every 60 s.
const _staleAfter = Duration(minutes: 3);

/// One sensor tile: how to read it from telemetry and how to draw it.
class _Sensor {
  const _Sensor({
    required this.name,
    required this.unit,
    required this.icon,
    required this.colors,
    required this.read,
    required this.format,
    required this.decimals,
  });
  final String name, unit;
  final IconData icon;
  final List<Color> colors;
  final double Function(PantryTelemetry) read;
  final String Function(double) format;
  final int decimals;
}

final _sensors = <_Sensor>[
  _Sensor(
    name: 'MQ-3',
    unit: 'ppm',
    icon: Icons.wifi_tethering_rounded,
    colors: _lightViolet,
    read: (t) => t.mq3Ppm,
    format: formatPpm,
    decimals: 1,
  ),
  _Sensor(
    name: 'MQ-135',
    unit: 'ppm',
    icon: Icons.wifi_tethering_rounded,
    colors: _lightViolet,
    read: (t) => t.mq135Ppm,
    format: formatPpm,
    decimals: 1,
  ),
  _Sensor(
    name: 'Temperature',
    unit: '°C',
    icon: Icons.thermostat_rounded,
    colors: Clay.peach,
    read: (t) => t.tempC,
    format: (v) => v.toStringAsFixed(1),
    decimals: 1,
  ),
  _Sensor(
    name: 'Humidity',
    unit: '%',
    icon: Icons.water_drop_rounded,
    colors: Clay.sky,
    read: (t) => t.rhPct,
    format: (v) => v.toStringAsFixed(0),
    decimals: 0,
  ),
];

class PantryScreen extends ConsumerStatefulWidget {
  const PantryScreen({super.key});

  @override
  ConsumerState<PantryScreen> createState() => _PantryScreenState();
}

class _PantryScreenState extends ConsumerState<PantryScreen> {
  // Kept in this State, and both crops render through the same page widget, so
  // switching crop never resets the scroll position.
  int _crop = 0;

  Future<void> _refresh() => Future.wait([
    ref.read(bananaPantryProvider.notifier).refresh(),
    ref.read(potatoPantryProvider.notifier).refresh(),
  ]);

  void _openHistory(_Sensor sensor) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Clay.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
      ),
      builder: (_) => _HistorySheet(sensor: sensor, compartment: _crops[_crop]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compartment = _crops[_crop];
    final provider = _crop == 0 ? bananaPantryProvider : potatoPantryProvider;
    final value = ref.watch(provider);
    const header = ClayScreenHeader(label: 'Produce storage', title: 'Pantry');
    final switcher = ClaySegmented(
      labels: const ['Banana', 'Potato'],
      selected: _crop,
      onChanged: (i) => setState(() => _crop = i),
    );

    final data = value.value;
    if (data == null) {
      return ClayPage(
        onRefresh: _refresh,
        children: [
          header,
          const SizedBox(height: 22),
          switcher,
          const SizedBox(height: 22),
          value.hasError
              ? ClayMessageCard(
                message: userFacingError(value.error!),
                onRetry: ref.read(provider.notifier).refresh,
              )
              : ClayMessageCard(message: 'Reading the $compartment sensors...'),
        ],
      );
    }

    final stage = stageView(data.prediction.stage);
    final stale = DateTime.now().difference(data.raw.ts) > _staleAfter;
    return ClayPage(
      onRefresh: _refresh,
      children: [
        header,
        const SizedBox(height: 22),
        switcher,
        const SizedBox(height: 22),
        ClayEntrance(
          index: 0,
          child: _FreshnessCard(prediction: data.prediction, stage: stage),
        ),
        const SizedBox(height: 16),
        ClayEntrance(
          index: 1,
          child: _ShelfLifeCard(
            hours: data.prediction.rslH,
            updated: data.raw.ts,
            stale: stale,
          ),
        ),
        const SizedBox(height: 28),
        const ClaySectionTitle(
          'Sensor readings',
          subtitle: 'Conditions inside the pantry (shared by both items)',
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < _sensors.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 14),
          ClayEntrance(
            index: 2 + i ~/ 2,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _SensorTile(
                      sensor: _sensors[i],
                      telemetry: data.raw,
                      onTap: () => _openHistory(_sensors[i]),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _SensorTile(
                      sensor: _sensors[i + 1],
                      telemetry: data.raw,
                      onTap: () => _openHistory(_sensors[i + 1]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 26),
        Center(
          child: Text(
            'Pull down to refresh. Tap a sensor for its history.',
            style: Clay.text(12, weight: 700, color: Clay.mutedWarm),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Freshness
// ---------------------------------------------------------------------------

class _FreshnessCard extends StatelessWidget {
  const _FreshnessCard({required this.prediction, required this.stage});
  final PantryPrediction prediction;
  final StageView stage;

  @override
  Widget build(BuildContext context) {
    final score = prediction.freshnessScore.clamp(0, 100).toDouble();
    return ClayBox(
      radius: 34,
      color: stage.card,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      semanticLabel:
          'Freshness ${score.round()} percent, ${stage.word}. ${stage.tip}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Freshness', style: Clay.text(20, weight: 900)),
                    const SizedBox(height: 2),
                    Text(
                      'Live produce quality estimate',
                      style: Clay.text(13.5, weight: 600, color: Clay.mutedGreen),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ClayPill(
                label: stage.word,
                background: stage.pillBg,
                foreground: stage.pillFg,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _Donut(score: score, fill: stage.fill, track: stage.track),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClayProgress(
                      value: score / 100,
                      colors: stage.fill,
                      height: 14,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      stage.tip,
                      style: Clay.text(
                        13.5,
                        weight: 600,
                        color: Clay.mutedGreen,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (prediction.source != 'model') ...[
            const SizedBox(height: 14),
            Text(
              'Estimated from the shared gas sensors (rule-based, not the trained model yet).',
              style: Clay.text(12, weight: 600, color: Clay.mutedWarm, height: 1.3),
            ),
          ],
        ],
      ),
    );
  }
}

/// Clay donut: a sunken track, a gradient arc of [score] percent and an inset
/// centre showing the number.
class _Donut extends StatelessWidget {
  const _Donut({required this.score, required this.fill, required this.track});
  final double score;
  final List<Color> fill;
  final Color track;

  static const _size = 96.0;
  static const _stroke = 14.0;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: SizedBox(
        width: _size,
        height: _size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: score),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder:
              (context, shown, _) => Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _DonutPainter(
                        fraction: shown / 100,
                        fill: fill,
                        track: track,
                      ),
                    ),
                  ),
                  Container(
                    width: _size - 2 * _stroke - 6,
                    height: _size - 2 * _stroke - 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Clay.cardWarning,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.7),
                          offset: const Offset(0, 2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    foregroundDecoration: BoxDecoration(
                      shape: BoxShape.circle,
                      // Inset shadow: darker along the top rim.
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0, 0.5],
                        colors: [
                          Clay.shadowTint.withValues(alpha: 0.18),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${shown.round()}%',
                      style: Clay.text(24, weight: 900),
                    ),
                  ),
                ],
              ),
        ),
      ),
    ),
  );
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.fraction,
    required this.fill,
    required this.track,
  });
  final double fraction;
  final List<Color> fill;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = _Donut._stroke;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    final f = fraction.isNaN ? 0.0 : fraction.clamp(0.0, 1.0);
    if (f <= 0) return;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-math.pi / 2); // start at 12 o'clock
    canvas.translate(-size.width / 2, -size.height / 2);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2 * f,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: [fill.first, fill.last],
          endAngle: math.pi * 2,
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.fraction != fraction || old.fill != fill || old.track != track;
}

// ---------------------------------------------------------------------------
// Shelf life
// ---------------------------------------------------------------------------

class _ShelfLifeCard extends StatelessWidget {
  const _ShelfLifeCard({
    required this.hours,
    required this.updated,
    required this.stale,
  });
  final double hours;
  final DateTime updated;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final text = formatShelfLife(hours);
    return ClayBox(
      radius: 30,
      color: Clay.cardWarning,
      padding: const EdgeInsets.all(18),
      semanticLabel:
          'Remaining shelf life $text. Updated ${clockTime(updated)}'
          '${stale ? ', no new data' : ''}',
      child: Row(
        children: [
          const ClayIconBlob(
            icon: Icons.schedule_rounded,
            colors: Clay.sky,
            size: 62,
            radius: 22,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Remaining shelf life',
                  style: Clay.text(13, weight: 700, color: Clay.mutedWarm),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  layoutBuilder:
                      (current, previous) => Stack(
                        alignment: Alignment.centerLeft,
                        children: [...previous, if (current != null) current],
                      ),
                  child: Text(
                    text,
                    key: ValueKey(text),
                    style: Clay.text(34, weight: 900, height: 1.15),
                  ),
                ),
                Text(
                  stale
                      ? 'Updated ${clockTime(updated)} · waiting for new reading'
                      : 'Updated ${clockTime(updated)}',
                  style: Clay.text(
                    12,
                    weight: 700,
                    color: stale ? Clay.warnPillText : Clay.mutedWarm,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sensors
// ---------------------------------------------------------------------------

class _SensorTile extends StatelessWidget {
  const _SensorTile({
    required this.sensor,
    required this.telemetry,
    required this.onTap,
  });
  final _Sensor sensor;
  final PantryTelemetry telemetry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final value = sensor.format(sensor.read(telemetry));
    return ClayBox(
      radius: 28,
      color: Clay.cardWarning,
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      semanticLabel:
          '${sensor.name} $value ${sensor.unit == '°C' ? 'degrees' : sensor.unit}. Tap for history',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClayIconBlob(
            icon: sensor.icon,
            colors: sensor.colors,
            size: 44,
            radius: 16,
          ),
          const SizedBox(height: 14),
          Text(
            sensor.name,
            style: Clay.text(13, weight: 700, color: Clay.mutedWarm),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: Clay.text(26, weight: 900)),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                sensor.unit,
                style: Clay.text(13, weight: 700, color: Clay.mutedWarm),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HistorySheet extends ConsumerWidget {
  const _HistorySheet({required this.sensor, required this.compartment});
  final _Sensor sensor;
  final String compartment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(pantryHistoryProvider(compartment));
    final label = '${compartment[0].toUpperCase()}${compartment.substring(1)}';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Clay.screenPadding,
          12,
          Clay.screenPadding,
          24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Clay.mutedWarm.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                ClayIconBlob(
                  icon: sensor.icon,
                  colors: sensor.colors,
                  size: 48,
                  radius: 18,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${sensor.name} history',
                        style: Clay.text(20, weight: 900),
                      ),
                      Text(
                        '$label box, last 24 hours',
                        style: Clay.text(13.5, weight: 600, color: Clay.mutedWarm),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ClayBox(
              radius: 28,
              color: Clay.cardWarning,
              padding: const EdgeInsets.fromLTRB(8, 22, 18, 12),
              semanticLabel: '${sensor.name} over the last 24 hours',
              child: SizedBox(
                height: 230,
                child: history.when(
                  loading:
                      () => Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Clay.violet.last,
                        ),
                      ),
                  error:
                      (error, _) => Center(
                        child: Text(
                          userFacingError(error),
                          textAlign: TextAlign.center,
                          style: Clay.text(
                            14,
                            weight: 700,
                            color: Clay.mutedGreen,
                          ),
                        ),
                      ),
                  data:
                      (rows) => ClayLineChart(
                        points: [
                          for (final r in rows) (r.raw.ts, sensor.read(r.raw)),
                        ],
                        unit: sensor.unit,
                        decimals: sensor.decimals,
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
