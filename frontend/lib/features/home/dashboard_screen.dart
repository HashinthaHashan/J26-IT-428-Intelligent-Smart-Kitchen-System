import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/clay.dart';
import '../alerts/alerts_providers.dart';
import '../../shared/widgets/clay_layout.dart';
import '../child/child_providers.dart';
import '../lpg/lpg_providers.dart';
import '../pantry/pantry_providers.dart';
import '../pest/pest_providers.dart';
import 'home_status.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  Future<void> _refresh(WidgetRef ref) => Future.wait([
    ref.read(lpgProvider.notifier).refresh(),
    ref.read(bananaPantryProvider.notifier).refresh(),
    ref.read(potatoPantryProvider.notifier).refresh(),
    ref.read(pestProvider.notifier).refresh(),
    ref.read(childProvider.notifier).refresh(),
    ref.read(alertsProvider.notifier).refresh(),
  ]);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final systems = ref.watch(homeSystemsProvider);
    final attention = systems.where((s) => s.needsAttention).toList();
    final healthy = systems.where((s) => s.severity == Severity.ok).toList();
    final waiting = systems.where((s) => !s.isLive).toList();
    final tiles = healthy.where((s) => s.compact == CompactStyle.tile).toList();
    final rows = healthy.where((s) => s.compact == CompactStyle.row).toList();
    final summary = HomeSummary.from(systems);
    final lastUpdate = systems
        .map((s) => s.updated)
        .whereType<DateTime>()
        .fold<DateTime?>(
          null,
          (latest, t) => latest == null || t.isAfter(latest) ? t : latest,
        );

    return ClayPage(
      onRefresh: () => _refresh(ref),
      children: [
        ClayScreenHeader(label: greetingFor(DateTime.now()), title: 'KitchenGuard'),
        const SizedBox(height: 22),
        ClayEntrance(index: 0, child: _SummaryCard(summary: summary)),
        if (attention.isNotEmpty) ...[
          const SizedBox(height: 26),
          ClaySectionTitle(
            'Take a look',
            trailing: lastUpdate == null ? null : 'Updated ${_ago(lastUpdate)}',
          ),
          for (final (i, system) in attention.indexed) ...[
            const SizedBox(height: 14),
            ClayEntrance(
              key: ValueKey(system.id),
              index: i + 1,
              child: _AttentionCard(system: system),
            ),
          ],
        ],
        if (healthy.isNotEmpty) ...[
          const SizedBox(height: 28),
          const ClaySectionTitle('All good'),
          const SizedBox(height: 14),
          for (var i = 0; i < tiles.length; i += 2) ...[
            if (i > 0) const SizedBox(height: 14),
            ClayEntrance(
              key: ValueKey('tiles-$i'),
              index: attention.length + 2 + i,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _HealthyTile(tiles[i])),
                    const SizedBox(width: 14),
                    Expanded(
                      child: i + 1 < tiles.length
                          ? _HealthyTile(tiles[i + 1])
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          ],
          for (final system in rows) ...[
            const SizedBox(height: 14),
            ClayEntrance(
              key: ValueKey(system.id),
              index: attention.length + 3,
              child: _CompactRow(system: system),
            ),
          ],
        ],
        if (waiting.isNotEmpty) ...[
          const SizedBox(height: 28),
          const ClaySectionTitle('Waiting for data'),
          for (final system in waiting) ...[
            const SizedBox(height: 14),
            _CompactRow(system: system),
          ],
        ],
        const SizedBox(height: 26),
        Center(
          child: Text(
            'Pull down to refresh all systems',
            style: Clay.text(12, weight: 700, color: Clay.mutedWarm),
          ),
        ),
      ],
    );
  }
}

String _ago(DateTime time) {
  final difference = DateTime.now().difference(time);
  if (difference.inSeconds < 60) return 'just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
  return '${difference.inHours} h ago';
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});
  final HomeSummary summary;

  @override
  Widget build(BuildContext context) => ClayBox(
    radius: 34,
    gradient: clayGradient(Clay.violet),
    padding: const EdgeInsets.fromLTRB(24, 22, 20, 24),
    semanticLabel: '${summary.title}. ${summary.subtitle} ${summary.livePill}',
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const ClayPulsingDot(),
                      const SizedBox(width: 8),
                      Text(
                        summary.livePill,
                        style: Clay.text(
                          12.5,
                          weight: 800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                summary.title,
                style: Clay.text(
                  25,
                  weight: 900,
                  color: Colors.white,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                summary.subtitle,
                style: Clay.text(
                  14.5,
                  weight: 600,
                  color: Colors.white.withValues(alpha: 0.88),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        const ClayFloating(
          child: ClayIconBlob(
            icon: Icons.verified_user_outlined,
            colors: [Color(0xFFFFFFFF), Color(0xFFF1F1FF)],
            iconColor: Color(0xFF1B1830),
            size: 66,
            radius: 24,
          ),
        ),
      ],
    ),
  );
}

({Color bg, Color fg}) _pillColors(Severity severity) => switch (severity) {
  Severity.critical => (bg: Clay.alertPillBg, fg: Clay.alertPillText),
  Severity.warning => (bg: Clay.warnPillBg, fg: Clay.warnPillText),
  Severity.ok => (bg: Clay.okPillBg, fg: Clay.okPillText),
  Severity.unknown => (bg: Clay.neutralPillBg, fg: Clay.neutralPillText),
};

Widget _pill(SystemStatus s) {
  final c = _pillColors(s.severity);
  return ClayPill(label: s.pillLabel, background: c.bg, foreground: c.fg);
}

String _semantics(SystemStatus s) => [
  s.title,
  s.pillLabel,
  if (s.headline != null) s.headline!,
  if (s.value != null) '${s.value} ${s.unit == '%' ? 'percent' : s.unit ?? ''}',
  if (s.tip != null) s.tip!,
].join(', ');

List<Color> _barColors(Severity severity) => switch (severity) {
  Severity.critical => Clay.coral,
  Severity.warning => Clay.peach,
  _ => Clay.sage,
};

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({required this.system});
  final SystemStatus system;

  @override
  Widget build(BuildContext context) {
    final s = system;
    return ClayBox(
      radius: 30,
      color: s.severity == Severity.critical ? const Color(0xFFFDF2EF) : Clay.cardWarning,
      padding: const EdgeInsets.all(20),
      semanticLabel: _semantics(s),
      onTap: () => context.go(s.route),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClayIconBlob(icon: s.icon, colors: s.iconColors),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.title, style: Clay.text(17, weight: 800)),
                    Text(
                      s.subtitle,
                      style: Clay.text(14, weight: 600, color: Clay.mutedGreen),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _pill(s),
            ],
          ),
          const SizedBox(height: 18),
          if (s.value != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(s.value!, style: Clay.text(40, weight: 900, height: 1)),
                const SizedBox(width: 5),
                Text(
                  s.unit ?? '',
                  style: Clay.text(17, weight: 700, color: Clay.mutedGreen),
                ),
                const Spacer(),
                if (s.limitLabel != null)
                  Text(
                    s.limitLabel!,
                    style: Clay.text(13, weight: 700, color: Clay.mutedGreen),
                  ),
              ],
            ),
            if (s.progress != null) ...[
              const SizedBox(height: 14),
              ClayProgress(value: s.progress!, colors: _barColors(s.severity)),
            ],
          ] else if (s.headline != null)
            Text(s.headline!, style: Clay.text(24, weight: 900, height: 1.15)),
          if (s.tip != null) ...[
            const SizedBox(height: 12),
            Text(
              s.tip!,
              style: Clay.text(14, weight: 600, color: Clay.ink.withValues(alpha: 0.78), height: 1.35),
            ),
          ],
        ],
      ),
    );
  }
}

class _HealthyTile extends StatelessWidget {
  const _HealthyTile(this.system);
  final SystemStatus system;

  @override
  Widget build(BuildContext context) {
    final s = system;
    return ClayBox(
      radius: 28,
      color: Clay.cardHealthy,
      padding: const EdgeInsets.all(16),
      semanticLabel: _semantics(s),
      onTap: () => context.go(s.route),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClayIconBlob(icon: s.icon, colors: s.iconColors, size: 46, radius: 16),
              const Spacer(),
              _pill(s),
            ],
          ),
          const SizedBox(height: 14),
          Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Clay.text(16, weight: 800)),
          Text(s.subtitle, style: Clay.text(13.5, weight: 600, color: Clay.mutedGreen)),
          const Spacer(),
          const SizedBox(height: 8),
          if (s.value != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(s.value!, style: Clay.text(30, weight: 900, height: 1.1)),
                Text(s.unit ?? '', style: Clay.text(22, weight: 900)),
              ],
            ),
          if (s.progress != null) ...[
            const SizedBox(height: 10),
            ClayProgress(value: s.progress!, colors: _barColors(s.severity), height: 10),
          ],
        ],
      ),
    );
  }
}

class _CompactRow extends StatelessWidget {
  const _CompactRow({required this.system});
  final SystemStatus system;

  @override
  Widget build(BuildContext context) {
    final s = system;
    final detail = s.value == null ? s.subtitle : '${s.subtitle} · ${s.value} ${s.unit ?? ''}';
    return ClayBox(
      radius: 28,
      color: s.isLive ? Clay.cardHealthy : Clay.cardWarning,
      padding: const EdgeInsets.all(16),
      semanticLabel: _semantics(s),
      onTap: () => context.go(s.route),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            ClayIconBlob(icon: s.icon, colors: s.iconColors, size: 46, radius: 16),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.title, style: Clay.text(16, weight: 800)),
                  Text(detail, style: Clay.text(13.5, weight: 600, color: Clay.mutedGreen)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _pill(s),
          ],
        ),
      ),
    );
  }
}
