import '../../models/pest.dart';

/// What the camera concluded for one event.
enum PestResult { cockroach, rat, nonPest, none }

PestResult resultOf(PestEvent event) => switch (event.yoloPred) {
  'cockroach' => PestResult.cockroach,
  'rat' => PestResult.rat,
  'non_pest' => PestResult.nonPest,
  _ => PestResult.none, // null, 'none', 'not_in_view'
};

extension PestResultX on PestResult {
  bool get isPest => this == PestResult.cockroach || this == PestResult.rat;

  /// The word shown in the pill (result = colour + word + percent).
  String? get label => switch (this) {
    PestResult.cockroach => 'cockroach',
    PestResult.rat => 'rat',
    PestResult.nonPest => 'non-pest',
    PestResult.none => null,
  };
}

bool isSameLocalDay(DateTime a, DateTime b) {
  final x = a.toLocal(), y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

/// Numbers and copy for the summary card. Pass the events of the selected
/// zone (already filtered); everything is recalculated from them.
class PestSummary {
  const PestSummary({
    required this.zoneLabel,
    required this.headline,
    required this.subtitle,
    required this.cockroachCount,
    required this.otherCount,
    required this.pestCount,
    required this.topMatchPct,
  });

  final String zoneLabel, headline, subtitle;
  final int cockroachCount, otherCount, pestCount;
  final int? topMatchPct;

  factory PestSummary.from(
    Iterable<PestEvent> events, {
    required String zone,
    required bool allZones,
    DateTime? now,
  }) {
    final today = (now ?? DateTime.now());
    final todays = events.where((e) => isSameLocalDay(e.ts, today)).toList();
    final pests = todays.where((e) => resultOf(e).isPest).toList();
    final cockroaches =
        pests.where((e) => resultOf(e) == PestResult.cockroach).length;
    final rats = pests.length - cockroaches;

    final species =
        rats == 0 ? 'cockroach' : (cockroaches == 0 ? 'rat' : 'pest');
    final headline =
        pests.isEmpty
            ? 'No pests spotted'
            : '${pests.length} $species '
                '${pests.length == 1 ? 'sighting' : 'sightings'} today';

    final confs = pests.map((e) => e.yoloConf).whereType<double>();
    final top =
        confs.isEmpty
            ? null
            : (confs.reduce((a, b) => a > b ? a : b) * 100).round();

    String subtitle;
    if (pests.isEmpty) {
      subtitle = 'Nothing detected today. Monitoring continues.';
    } else {
      final source = _mostCommon(pests.map((e) => e.triggerSource));
      final where = _mostCommon(pests.map((e) => e.zone)).toLowerCase();
      subtitle =
          pests.length == 1
              ? '$source caught it. Check the $where first.'
              : '$source caught the most. Check the $where first.';
    }

    return PestSummary(
      zoneLabel: allZones ? 'all zones' : zone.toLowerCase(),
      headline: headline,
      subtitle: subtitle,
      cockroachCount: cockroaches,
      otherCount: todays.length - cockroaches,
      pestCount: pests.length,
      topMatchPct: top,
    );
  }
}

/// Most frequent value; ties go to the first one seen (newest event first).
String _mostCommon(Iterable<String> values) {
  final counts = <String, int>{};
  for (final v in values) {
    counts[v] = (counts[v] ?? 0) + 1;
  }
  var best = '';
  var bestCount = 0;
  counts.forEach((k, c) {
    if (c > bestCount) {
      best = k;
      bestCount = c;
    }
  });
  return best;
}
