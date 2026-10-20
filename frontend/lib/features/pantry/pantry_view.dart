import 'package:flutter/material.dart';

import '../../shared/widgets/clay.dart';

/// How a backend stage (Fresh / Ripe / Deteriorating / Spoiled) is shown:
/// a word, ring/bar colours, card tint and a one-line care tip. Status is always
/// colour + word + number, never colour alone.
class StageView {
  const StageView({
    required this.word,
    required this.fill,
    required this.track,
    required this.card,
    required this.pillBg,
    required this.pillFg,
    required this.tip,
  });

  final String word, tip;
  final List<Color> fill;
  final Color track, card, pillBg, pillFg;
}

const _sageFill = [Color(0xFFA6DCBB), Color(0xFF62B790)];
const _sageTrack = Color(0xFFDBE9DE);
const _warmTrack = Color(0xFFEFE7D9);
const _dangerCard = Color(0xFFFDF2EF);

StageView stageView(String stage) {
  switch (stage.toLowerCase()) {
    case 'ripe':
      return const StageView(
        word: 'Aging',
        fill: Clay.peach,
        track: _warmTrack,
        card: Clay.cardWarning,
        pillBg: Clay.warnPillBg,
        pillFg: Clay.warnPillText,
        tip: 'Ripening. Plan to use it within a day or two.',
      );
    case 'deteriorating':
      return const StageView(
        word: 'Spoiling',
        fill: Clay.coral,
        track: _warmTrack,
        card: _dangerCard,
        pillBg: Clay.alertPillBg,
        pillFg: Clay.alertPillText,
        tip: 'Going off. Use it soon and check it for soft or dark spots.',
      );
    case 'spoiled':
      return const StageView(
        word: 'Spoiled',
        fill: Clay.coral,
        track: _warmTrack,
        card: _dangerCard,
        pillBg: Clay.alertPillBg,
        pillFg: Clay.alertPillText,
        tip: 'Past its best. Check it and throw it out if it smells off.',
      );
    default: // Fresh
      return const StageView(
        word: 'Fresh',
        fill: _sageFill,
        track: _sageTrack,
        card: Clay.cardHealthy,
        pillBg: Clay.okPillBg,
        pillFg: Clay.okPillText,
        tip: 'Looking great. Keep it cool and dry.',
      );
  }
}

/// "6d 21h", "5h 30m", "under 1h" or "0h" from remaining hours.
String formatShelfLife(double hours) {
  if (hours.isNaN || hours <= 0) return '0h';
  if (hours < 1) return 'under 1h';
  final total = hours.floor();
  final days = total ~/ 24;
  final h = total % 24;
  if (days >= 1) return '${days}d ${h}h';
  final m = ((hours - total) * 60).round();
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// Gas readings span ~0.1 to thousands of ppm: keep small numbers readable.
String formatPpm(double v) => v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

String clockTime(DateTime t) {
  final l = t.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}
