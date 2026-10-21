import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../core/device_presence.dart';
import '../../models/pest.dart';
import '../../shared/widgets/clay.dart';
import '../../shared/widgets/clay_layout.dart';
import '../../shared/widgets/device_status_banner.dart';
import 'pest_providers.dart';
import 'pest_summary.dart';
import 'trial_review_sheet.dart';

const _allZones = 'All zones';
const _zones = [
  _allZones,
  'Sink',
  'Pantry floor',
  'Trash bin',
  'Under cabinet',
  'Behind fridge',
];
const _pageStep = 20;
// The number of events to fetch from the backend at once. The UI can show fewer
const _lightViolet = [Color(0xFFC9CBFA), Color(0xFF8E91EC)];
const _cockroachPillBg = Color(0xFFFFE0DD);
const _cockroachPillFg = Color(0xFFB13A45);

class PestScreen extends ConsumerStatefulWidget {
  const PestScreen({super.key});

  @override
  ConsumerState<PestScreen> createState() => _PestScreenState();
}

class _PestScreenState extends ConsumerState<PestScreen> {
  String _zone = _allZones;
  int _shown = _pageStep;

  Future<void> _refresh() async {
    await Future.wait([
      ref.read(devicePresenceProvider.notifier).refresh(),
      ref.read(pestProvider.notifier).refresh(),
    ]);
  }

  void _selectZone(String zone) => setState(() {
    _zone = zone;
    _shown = _pageStep;
  });

  Future<void> _showMore(PestState data, int remainingLocal) async {
    if (remainingLocal > 0) {
      setState(() => _shown += _pageStep);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(pestProvider.notifier).loadMore();
      if (mounted) setState(() => _shown += _pageStep);
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(userFacingError(error))));
    }
  }

  void _review(DeterrenceTrial trial) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Clay.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
      ),
      builder: (_) => TrialReviewSheet(
        trial: trial,
        onSubmit: (verdict) =>
            ref.read(pestProvider.notifier).review(trial, verdict),
      ),
    );
  }

  void _openEvent(PestEvent event) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Clay.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
      ),
      builder: (_) => _EventSheet(event: event),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(pestProvider.notifier);
    final value = ref.watch(pestProvider);
    final availability = ref.watch(
      deviceAvailabilityProvider((
        component: 'pest',
        deviceId: AppConfig.pestDeviceId,
      )),
    );
    const header = ClayScreenHeader(label: 'Pest monitoring', title: 'Pest');

    if (availability == DeviceAvailability.offline) {
      return ClayPage(
        onRefresh: _refresh,
        children: [
          header,
          const SizedBox(height: 22),
          ClayMessageCard(
            message:
                'Pest device is offline. Connect power to resume live monitoring.',
            onRetry: _refresh,
          ),
        ],
      );
    }

    final data = value.value;
    if (data == null) {
      return ClayPage(
        onRefresh: _refresh,
        children: [
          header,
          const SizedBox(height: 22),
          if (availability == DeviceAvailability.online) ...[
            const DeviceOnlineBanner(),
            const SizedBox(height: 14),
          ],
          value.hasError
              ? ClayMessageCard(
                  message: userFacingError(value.error!),
                  onRetry: notifier.refresh,
                )
              : const ClayMessageCard(message: 'Loading pest activity...'),
        ],
      );
    }

    final allZones = _zone == _allZones;
    // Newest first, whatever order the backend / live frames arrived in.
    final sorted = [...data.events]
      ..sort((a, b) => b.event.ts.compareTo(a.event.ts));
    final inZone = allZones
        ? sorted
        : sorted.where((e) => e.event.zone == _zone).toList();
    final summary = PestSummary.from(
      inZone.map((e) => e.event),
      zone: _zone,
      allZones: allZones,
    );
    final visible = inZone.take(_shown).toList();
    final remainingLocal = inZone.length - visible.length;
    final canLoadMore = remainingLocal > 0 || data.hasMore;

    return ClayPage(
      onRefresh: _refresh,
      children: [
        header,
        const SizedBox(height: 22),
        const DeviceOnlineBanner(),
        const SizedBox(height: 14),
        ClayEntrance(index: 0, child: _SummaryCard(summary: summary)),
        if (data.pendingTrials.isNotEmpty) ...[
          const SizedBox(height: 28),
          const ClaySectionTitle(
            'Pending reviews',
            subtitle: 'Confirm automated deterrence results',
          ),
          for (final trial in data.pendingTrials) ...[
            const SizedBox(height: 14),
            _TrialCard(trial: trial, onReview: () => _review(trial)),
          ],
        ],
        const SizedBox(height: 28),
        const ClaySectionTitle('Zone'),
        const SizedBox(height: 12),
        _ZoneChips(selected: _zone, onSelected: _selectZone),
        const SizedBox(height: 24),
        ClaySectionTitle(
          'Detection history',
          subtitle: 'Events from ${allZones ? 'all zones' : _zone}',
        ),
        const SizedBox(height: 14),
        if (visible.isEmpty)
          _EmptyCard(
            message: data.events.isEmpty
                ? 'No pest events yet'
                : 'No events in $_zone yet',
          )
        else
          for (final (i, doc) in visible.indexed) ...[
            if (i > 0) const SizedBox(height: 14),
            ClayEntrance(
              key: ValueKey(
                '${doc.event.ts.microsecondsSinceEpoch}-${doc.event.zone}'
                '-${doc.event.triggerSource}',
              ),
              index: i < 6 ? i + 1 : 0,
              child: _EventCard(
                event: doc.event,
                onTap: () => _openEvent(doc.event),
              ),
            ),
          ],
        if (canLoadMore) ...[
          const SizedBox(height: 18),
          Center(
            child: _MoreButton(
              loading: data.loadingMore,
              onTap: () => _showMore(data, remainingLocal),
            ),
          ),
        ],
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

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});
  final PestSummary summary;

  @override
  Widget build(BuildContext context) => ClayBox(
    radius: 34,
    gradient: clayGradient(Clay.violet),
    padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
    semanticLabel:
        '${summary.headline}. ${summary.subtitle} '
        '${summary.cockroachCount} cockroach, ${summary.otherCount} other events',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ClayPulsingDot(),
                const SizedBox(width: 8),
                Text(
                  'Monitoring ${summary.zoneLabel}',
                  style: Clay.text(12.5, weight: 800, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        _Swap(
          child: Text(
            summary.headline,
            key: ValueKey(summary.headline),
            style: Clay.text(
              25,
              weight: 900,
              color: Colors.white,
              height: 1.15,
            ),
          ),
        ),
        const SizedBox(height: 6),
        _Swap(
          child: Text(
            summary.subtitle,
            key: ValueKey(summary.subtitle),
            style: Clay.text(
              14.5,
              weight: 600,
              color: Colors.white.withValues(alpha: 0.88),
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _GlassTile(
                value: '${summary.cockroachCount}',
                label: 'Cockroach',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _GlassTile(
                value: '${summary.otherCount}',
                label: 'Other events',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _GlassTile(
                value: summary.topMatchPct == null
                    ? '–'
                    : '${summary.topMatchPct}%',
                label: 'Top match',
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

/// Cross-fades text when the filter changes the numbers.
class _Swap extends StatelessWidget {
  const _Swap({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 220),
    layoutBuilder: (current, previous) => Stack(
      alignment: Alignment.centerLeft,
      children: [...previous, if (current != null) current],
    ),
    child: child,
  );
}

class _GlassTile extends StatelessWidget {
  const _GlassTile({required this.value, required this.label});
  final String value, label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      // Inset glass: lighter fill, darker rim along the top edge.
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0, 0.45],
        colors: [
          const Color(0xFF2A2B8A).withValues(alpha: 0.18),
          Colors.white.withValues(alpha: 0.16),
        ],
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Swap(
            child: Text(
              value,
              key: ValueKey(value),
              style: Clay.text(
                24,
                weight: 900,
                color: Colors.white,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Clay.text(
              12,
              weight: 700,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Zone filter
// ---------------------------------------------------------------------------

class _ZoneChips extends StatelessWidget {
  const _ZoneChips({required this.selected, required this.onSelected});
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    // Let the chips' soft shadows spill outside the row instead of being cut.
    clipBehavior: Clip.none,
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        for (final zone in _zones) ...[
          _Chip(
            label: zone,
            selected: zone == selected,
            onTap: () => onSelected(zone),
          ),
          const SizedBox(width: 12),
        ],
      ],
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    label: '$label filter',
    excludeSemantics: true,
    onTap: onTap,
    child: ClayBox(
      radius: 26,
      depth: 0.7,
      color: Clay.navBar,
      gradient: selected ? clayGradient(Clay.violet) : null,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Center(
          widthFactor: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Text(
              label,
              style: Clay.text(
                14.5,
                weight: 800,
                color: selected ? Colors.white : Clay.mutedWarm,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// History
// ---------------------------------------------------------------------------

String _time(DateTime date) {
  final d = date.toLocal();
  return '${d.month}/${d.day} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

IconData _sensorIcon(String source) => switch (source) {
  'Camera' => Icons.photo_camera_outlined,
  'PIR' => Icons.wifi_tethering_rounded,
  'IR' => Icons.sensors_rounded,
  'Vibration' => Icons.vibration_rounded,
  _ => Icons.track_changes_rounded,
};

List<Color> _resultColors(PestResult r) => switch (r) {
  PestResult.cockroach || PestResult.rat => Clay.coral,
  PestResult.nonPest => Clay.sage,
  PestResult.none => _lightViolet,
};

({Color bg, Color fg}) _pillColors(PestResult r) => r == PestResult.nonPest
    ? (bg: Clay.okPillBg, fg: Clay.okPillText)
    : (bg: _cockroachPillBg, fg: _cockroachPillFg);

String _resultWords(PestEvent e) {
  final r = resultOf(e);
  if (r.label == null) return 'no result';
  final pct = e.yoloConf == null
      ? ''
      : ' ${(e.yoloConf! * 100).round()} percent';
  return '${r.label}$pct';
}

class _ResultPill extends StatelessWidget {
  const _ResultPill({required this.event});
  final PestEvent event;

  @override
  Widget build(BuildContext context) {
    final result = resultOf(event);
    final colors = _pillColors(result);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Clay.shadowTint.withValues(alpha: 0.14),
            offset: const Offset(2, 3),
            blurRadius: 6,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              result.label!,
              style: Clay.text(12, weight: 800, color: colors.fg),
            ),
            if (event.yoloConf != null)
              Text(
                '${(event.yoloConf! * 100).round()}%',
                style: Clay.text(
                  15,
                  weight: 900,
                  color: colors.fg,
                  height: 1.2,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.onTap});
  final PestEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final result = resultOf(event);
    return ClayBox(
      radius: 26,
      depth: 0.9,
      color: Clay.cardWarning,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      onTap: onTap,
      semanticLabel:
          '${event.zone}, ${event.triggerSource}, ${_time(event.ts)}, '
          '${_resultWords(event)}',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            ClayIconBlob(
              icon: _sensorIcon(event.triggerSource),
              colors: _resultColors(result),
              size: 48,
              radius: 18,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.zone,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Clay.text(16, weight: 800),
                  ),
                  Text(
                    '${event.triggerSource} · ${_time(event.ts)}',
                    style: Clay.text(13, weight: 600, color: Clay.mutedWarm),
                  ),
                ],
              ),
            ),
            if (result.label != null) ...[
              const SizedBox(width: 10),
              _ResultPill(event: event),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => ClayBox(
    radius: 26,
    color: Clay.cardHealthy,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
    semanticLabel: message,
    child: Column(
      children: [
        const ClayIconBlob(
          icon: Icons.track_changes_rounded,
          colors: _lightViolet,
          size: 52,
        ),
        const SizedBox(height: 14),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Clay.text(15.5, weight: 800, color: Clay.mutedGreen),
        ),
      ],
    ),
  );
}

class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.loading, required this.onTap});
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ClayBox(
    radius: 26,
    depth: 0.7,
    color: Clay.navBar,
    onTap: loading ? null : onTap,
    semanticLabel: 'Show older events',
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48, minWidth: 190),
      child: Center(
        widthFactor: 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: loading
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    color: Clay.violet.last,
                  ),
                )
              : Text(
                  'Show older events',
                  style: Clay.text(14.5, weight: 800, color: Clay.violet.last),
                ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Pending deterrence reviews
// ---------------------------------------------------------------------------

class _TrialCard extends StatelessWidget {
  const _TrialCard({required this.trial, required this.onReview});
  final DeterrenceTrial trial;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    // species is null when the deterrent fired on the device's fast path.
    final known = trial.species;
    final species = (known == null || known.isEmpty)
        ? 'Pest (not identified)'
        : '${known[0].toUpperCase()}${known.substring(1)}';
    return ClayBox(
      radius: 26,
      depth: 0.9,
      color: Clay.cardWarning,
      padding: const EdgeInsets.all(14),
      onTap: onReview,
      semanticLabel:
          'Review deterrence result, $species at ${trial.zone}, '
          'system verdict ${trial.systemVerdict}',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            const ClayIconBlob(
              icon: Icons.fact_check_outlined,
              colors: _lightViolet,
              size: 48,
              radius: 18,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$species · ${trial.zone}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Clay.text(16, weight: 800),
                  ),
                  Text(
                    'System verdict: ${trial.systemVerdict}',
                    style: Clay.text(13, weight: 600, color: Clay.mutedWarm),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const ClayPill(
              label: 'Review',
              background: Clay.warnPillBg,
              foreground: Clay.warnPillText,
              fontSize: 13.5,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Event detail
// ---------------------------------------------------------------------------

class _EventSheet extends StatelessWidget {
  const _EventSheet({required this.event});
  final PestEvent event;

  @override
  Widget build(BuildContext context) {
    final result = resultOf(event);
    final facts = <(String, String)>[
      ('Trigger', event.triggerSource),
      ('Motion (PIR)', event.pir ? 'Detected' : 'Not detected'),
      (
        'Vibration',
        '${event.vibRmsG.toStringAsFixed(2)} g'
            '${event.vibTrigger ? ' · triggered' : ''}',
      ),
      ('Ambient light', '${event.ambientLux.round()} lux'),
      ('Camera', event.cameraInView ? 'Subject in view' : 'Nothing in view'),
    ];
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
            const SizedBox(height: 20),
            Row(
              children: [
                ClayIconBlob(
                  icon: _sensorIcon(event.triggerSource),
                  colors: _resultColors(result),
                  size: 56,
                  radius: 20,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(event.zone, style: Clay.text(21, weight: 900)),
                      Text(
                        '${event.triggerSource} · ${_time(event.ts)}',
                        style: Clay.text(
                          14,
                          weight: 600,
                          color: Clay.mutedWarm,
                        ),
                      ),
                    ],
                  ),
                ),
                if (result.label != null) _ResultPill(event: event),
              ],
            ),
            const SizedBox(height: 20),
            ClayBox(
              radius: 26,
              depth: 0.8,
              color: Clay.cardWarning,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: Column(
                children: [
                  for (final fact in facts)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Text(
                            fact.$1,
                            style: Clay.text(
                              14,
                              weight: 700,
                              color: Clay.mutedWarm,
                            ),
                          ),
                          const Spacer(),
                          Text(fact.$2, style: Clay.text(14.5, weight: 800)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (event.triggerSource == 'Camera') ...[
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.photo_camera_outlined,
                    size: 18,
                    color: Clay.mutedWarm,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No snapshot is available: the camera node currently '
                      'sends its result and confidence, not the image.',
                      style: Clay.text(
                        12.5,
                        weight: 600,
                        color: Clay.mutedWarm,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
