import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/clay.dart';
import '../child/child_providers.dart';
import '../lpg/lpg_providers.dart';
import '../pantry/pantry_providers.dart';
import '../pest/pest_providers.dart';
import '../../models/lpg.dart';
import '../../models/pantry.dart';

/// Declaration order is the sort order: most severe first.
enum Severity { critical, warning, ok, unknown }

/// Which compact layout a healthy system uses in "All good".
enum CompactStyle { tile, row }

/// A single system on the Home screen, already reduced to display data.
class SystemStatus {
  const SystemStatus({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColors,
    required this.route,
    required this.severity,
    required this.pillLabel,
    this.compact = CompactStyle.row,
    this.value,
    this.unit,
    this.limitLabel,
    this.progress,
    this.headline,
    this.tip,
    this.updated,
  });

  final String id, title, subtitle, route, pillLabel;
  final IconData icon;
  final List<Color> iconColors;
  final Severity severity;
  final CompactStyle compact;

  /// Big number, e.g. `292`, with [unit] such as `ppm` or `%`.
  final String? value, unit, limitLabel;

  /// 0..1 fill of the progress groove.
  final double? progress;

  /// Text headline used instead of a number, e.g. `Cockroach spotted`.
  final String? headline;
  final String? tip;
  final DateTime? updated;

  bool get needsAttention =>
      severity == Severity.critical || severity == Severity.warning;
  bool get isLive => severity != Severity.unknown;
}

Severity severityOf(String status) {
  switch (status.toLowerCase()) {
    case 'critical':
    case 'danger':
    case 'dangerous':
    case 'spoiled':
      return Severity.critical;
    case 'warning':
    case 'ripe':
    case 'deteriorating':
      return Severity.warning;
    case 'safe':
    case 'fresh':
    case 'info':
      return Severity.ok;
    default:
      return Severity.unknown;
  }
}

/// Stable severity sort (critical, warning, ok, unknown); ties keep their
/// original order.
List<SystemStatus> sortBySeverity(Iterable<SystemStatus> systems) {
  final indexed = systems.toList().asMap().entries.toList()
    ..sort((a, b) {
      final bySeverity = a.value.severity.index.compareTo(
        b.value.severity.index,
      );
      return bySeverity != 0 ? bySeverity : a.key.compareTo(b.key);
    });
  return [for (final entry in indexed) entry.value];
}

const _lpgSafeLimitPpm = 1000.0;
const _pestRecency = Duration(minutes: 30);

SystemStatus lpgStatus(LpgSnapshot snapshot) {
  final severity = severityOf(snapshot.prediction.cloudTier);
  final ppm = snapshot.features.ppmComp;
  final (subtitle, tip) = switch (severity) {
    Severity.critical => (
      'Gas level is high',
      'Turn off the stove, open windows and step outside if you smell gas.',
    ),
    Severity.warning => (
      'Gas is a little above normal',
      'Tip: open a window and check the stove knobs.',
    ),
    _ => ('Air looks normal', 'Nothing to do right now.'),
  };
  return SystemStatus(
    id: 'lpg',
    title: 'LPG safety',
    subtitle: subtitle,
    icon: Icons.local_fire_department_rounded,
    iconColors: Clay.peach,
    route: '/lpg',
    severity: severity,
    pillLabel: _pill(snapshot.prediction.cloudTier),
    value: ppm.round().toString(),
    unit: 'ppm',
    limitLabel: 'Safe limit ${_lpgSafeLimitPpm.round()}',
    progress: ppm / _lpgSafeLimitPpm,
    tip: tip,
    updated: snapshot.raw.ts,
  );
}

SystemStatus pantryStatus({
  required String compartment,
  required PantrySnapshot snapshot,
}) {
  final stage = snapshot.prediction.stage;
  final severity = severityOf(stage);
  final score = snapshot.prediction.freshnessScore;
  final name = '${compartment[0].toUpperCase()}${compartment.substring(1)}';
  return SystemStatus(
    id: 'pantry-$compartment',
    title: '$name pantry',
    subtitle: 'Freshness',
    icon: compartment == 'banana' ? Icons.eco_rounded : Icons.spa_rounded,
    iconColors: Clay.sage,
    route: '/pantry',
    severity: severity,
    pillLabel: _pill(stage),
    compact: CompactStyle.tile,
    value: score.round().toString(),
    unit: '%',
    progress: score / 100,
    tip:
        severity == Severity.ok
            ? null
            : 'Use these soon, they are past their best.',
    updated: snapshot.raw.ts,
  );
}

SystemStatus pestStatus(PestState state, {DateTime? now}) {
  final events = state.events;
  final latest = events.isEmpty ? null : events.first.event;
  final detected =
      latest != null &&
      (latest.yoloPred == 'rat' || latest.yoloPred == 'cockroach') &&
      (now ?? DateTime.now()).difference(latest.ts) < _pestRecency;
  if (!detected) {
    return const SystemStatus(
      id: 'pest',
      title: 'Pest monitoring',
      subtitle: 'All zones checked',
      icon: Icons.track_changes_rounded,
      iconColors: Clay.coral,
      route: '/pest',
      severity: Severity.ok,
      pillLabel: 'All clear',
      headline: 'No pests lately',
    );
  }
  final species = latest.yoloPred!;
  return SystemStatus(
    id: 'pest',
    title: 'Pest monitoring',
    subtitle: 'All zones checked',
    icon: Icons.track_changes_rounded,
    iconColors: Clay.coral,
    route: '/pest',
    severity: Severity.warning,
    pillLabel: 'Warning',
    headline: '${species[0].toUpperCase()}${species.substring(1)} spotted',
    tip:
        'Seen ${_ago(latest.ts, now ?? DateTime.now())} in the '
        '${latest.zone.replaceAll('_', ' ')}. Check the sink and bin area first.',
    updated: latest.ts,
  );
}

SystemStatus childStatus(ChildState state) {
  final risk = state.snapshot.prediction.riskLevel;
  final severity = severityOf(risk);
  return SystemStatus(
    id: 'child',
    title: 'Child safety',
    subtitle: 'Live scene awareness',
    icon: Icons.sentiment_satisfied_rounded,
    iconColors: Clay.sky,
    route: '/child',
    severity: severity,
    pillLabel: severity == Severity.ok ? 'Area is clear' : _pill(risk),
    headline:
        severity == Severity.ok
            ? 'Area is clear'
            : (state.why ?? 'Check on your child'),
    tip:
        severity == Severity.ok
            ? null
            : 'Someone should look at the kitchen right now.',
    updated: state.snapshot.event.ts,
  );
}

/// Placeholder for a system whose data has not arrived yet.
SystemStatus unavailableStatus(SystemStatus template, {required bool loading}) =>
    SystemStatus(
      id: template.id,
      title: template.title,
      subtitle: loading ? 'Checking...' : 'Could not reach this system',
      icon: template.icon,
      iconColors: template.iconColors,
      route: template.route,
      severity: Severity.unknown,
      pillLabel: loading ? 'Checking' : 'Offline',
      compact: template.compact,
      tip: loading ? null : 'Pull down to try again.',
    );

String _pill(String status) =>
    status.isEmpty ? status : status[0].toUpperCase() + status.substring(1);

String _ago(DateTime time, DateTime now) {
  final difference = now.difference(time);
  if (difference.inSeconds < 60) return 'just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
  return '${difference.inHours} h ago';
}

SystemStatus _fromAsync<T>(
  AsyncValue<T> value,
  SystemStatus placeholder,
  SystemStatus Function(T) build,
) {
  // Prefer the last good value so a refresh or a blip never blanks a card.
  final data = value.value;
  if (data != null) return build(data);
  return unavailableStatus(placeholder, loading: value.isLoading);
}

const _lpgPlaceholder = SystemStatus(
  id: 'lpg',
  title: 'LPG safety',
  subtitle: '',
  icon: Icons.local_fire_department_rounded,
  iconColors: Clay.peach,
  route: '/lpg',
  severity: Severity.unknown,
  pillLabel: '',
);
const _bananaPlaceholder = SystemStatus(
  id: 'pantry-banana',
  title: 'Banana pantry',
  subtitle: '',
  icon: Icons.eco_rounded,
  iconColors: Clay.sage,
  route: '/pantry',
  severity: Severity.unknown,
  pillLabel: '',
  compact: CompactStyle.tile,
);
const _potatoPlaceholder = SystemStatus(
  id: 'pantry-potato',
  title: 'Potato pantry',
  subtitle: '',
  icon: Icons.spa_rounded,
  iconColors: Clay.sage,
  route: '/pantry',
  severity: Severity.unknown,
  pillLabel: '',
  compact: CompactStyle.tile,
);
const _pestPlaceholder = SystemStatus(
  id: 'pest',
  title: 'Pest monitoring',
  subtitle: '',
  icon: Icons.track_changes_rounded,
  iconColors: Clay.coral,
  route: '/pest',
  severity: Severity.unknown,
  pillLabel: '',
);
const _childPlaceholder = SystemStatus(
  id: 'child',
  title: 'Child safety',
  subtitle: '',
  icon: Icons.sentiment_satisfied_rounded,
  iconColors: Clay.sky,
  route: '/child',
  severity: Severity.unknown,
  pillLabel: '',
);

/// All five systems, derived from the live REST+WebSocket providers and
/// sorted so the most severe come first.
final homeSystemsProvider = Provider<List<SystemStatus>>(
  (ref) => sortBySeverity([
    _fromAsync(ref.watch(lpgProvider), _lpgPlaceholder, (d) => lpgStatus(d.latest)),
    _fromAsync(
      ref.watch(bananaPantryProvider),
      _bananaPlaceholder,
      (d) => pantryStatus(compartment: 'banana', snapshot: d),
    ),
    _fromAsync(
      ref.watch(potatoPantryProvider),
      _potatoPlaceholder,
      (d) => pantryStatus(compartment: 'potato', snapshot: d),
    ),
    _fromAsync(ref.watch(pestProvider), _pestPlaceholder, pestStatus),
    _fromAsync(ref.watch(childProvider), _childPlaceholder, childStatus),
  ]),
);

/// Summary-card copy derived from the system list.
class HomeSummary {
  const HomeSummary({
    required this.title,
    required this.subtitle,
    required this.live,
    required this.total,
  });

  final String title, subtitle;
  final int live, total;

  factory HomeSummary.from(List<SystemStatus> systems, {DateTime? now}) {
    final live = systems.where((s) => s.isLive).length;
    final critical = systems.where((s) => s.severity == Severity.critical).length;
    final attention = systems.where((s) => s.needsAttention).length;
    final offline = systems.length - live;
    final hour = (now ?? DateTime.now()).hour;
    final night = hour >= 17 || hour < 5;

    if (critical > 0) {
      return HomeSummary(
        title: 'Needs you right now',
        subtitle:
            critical == 1
                ? 'One thing needs attention straight away.'
                : '${_count(critical)} things need attention straight away.',
        live: live,
        total: systems.length,
      );
    }
    if (attention > 0) {
      return HomeSummary(
        title: 'Mostly calm ${night ? 'tonight' : 'today'}',
        subtitle:
            '${attention == 1 ? 'One thing could' : '${_count(attention)} things could'} '
            'use a quick look. Everything else is fine.',
        live: live,
        total: systems.length,
      );
    }
    if (offline > 0) {
      return HomeSummary(
        title: live == 0 ? 'Connecting...' : 'All calm so far',
        subtitle:
            live == 0
                ? 'Waiting for your kitchen systems to report in.'
                : 'Nothing needs you, but $offline ${offline == 1 ? 'system is' : 'systems are'} not reporting.',
        live: live,
        total: systems.length,
      );
    }
    return HomeSummary(
      title: 'All calm ${night ? 'tonight' : 'today'}',
      subtitle: 'Everything in your kitchen looks good.',
      live: live,
      total: systems.length,
    );
  }

  String get livePill =>
      live == total ? '$live systems live' : '$live of $total live';
}

String _count(int n) {
  const words = ['Zero', 'One', 'Two', 'Three', 'Four', 'Five'];
  return n < words.length ? words[n] : '$n';
}

String greetingFor(DateTime now) {
  final hour = now.hour;
  if (hour >= 5 && hour < 12) return 'Good morning';
  if (hour >= 12 && hour < 17) return 'Good afternoon';
  return 'Good evening';
}
