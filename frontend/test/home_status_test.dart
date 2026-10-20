import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchenguard/features/home/home_status.dart';
import 'package:kitchenguard/models/lpg.dart';
import 'package:kitchenguard/shared/widgets/clay.dart';
import 'package:kitchenguard/shared/widgets/clay_nav_bar.dart';

SystemStatus _system(String id, Severity severity) => SystemStatus(
  id: id,
  title: id,
  subtitle: '',
  icon: Icons.circle,
  iconColors: Clay.sage,
  route: '/',
  severity: severity,
  pillLabel: id,
);

LpgSnapshot _lpg(double ppm, String tier) => LpgSnapshot.fromJson({
  'raw': {
    'schema_version': 1,
    'device_id': 'lpg01',
    'ts': '2026-10-04T04:30:00Z',
    'seq': 1,
    'ppm_raw': ppm,
    'temp_c': 27.0,
    'rh_pct': 60.0,
    'fan_on': false,
    'window_frac': 0.0,
    'edge_tier': 'Safe',
    'edge_offline_mode': false,
  },
  'features': {
    'ppm_comp': ppm,
    'd_ppm_5s': 0,
    'slope_30s': 0,
    'ma10': ppm,
    'ma30': ppm,
    'd_rh_10s': 0,
    'tt700_s': 0,
  },
  'prediction': {'cloud_tier': tier, 'source': 'rules'},
});

void main() {
  test('severity words map to levels', () {
    expect(severityOf('Critical'), Severity.critical);
    expect(severityOf('Danger'), Severity.critical);
    expect(severityOf('Warning'), Severity.warning);
    expect(severityOf('Ripe'), Severity.warning);
    expect(severityOf('Fresh'), Severity.ok);
    expect(severityOf('Safe'), Severity.ok);
    expect(severityOf('???'), Severity.unknown);
  });

  test('systems sort critical, warning, ok and keep order within a level', () {
    final sorted = sortBySeverity([
      _system('a', Severity.ok),
      _system('b', Severity.warning),
      _system('c', Severity.unknown),
      _system('d', Severity.critical),
      _system('e', Severity.ok),
      _system('f', Severity.warning),
    ]);
    expect(sorted.map((s) => s.id), ['d', 'b', 'f', 'a', 'e', 'c']);
  });

  test('summary counts come from the list', () {
    final evening = DateTime(2026, 10, 6, 20);
    final summary = HomeSummary.from([
      _system('lpg', Severity.warning),
      _system('pest', Severity.warning),
      _system('b', Severity.ok),
      _system('p', Severity.ok),
      _system('c', Severity.ok),
    ], now: evening);
    expect(summary.livePill, '5 systems live');
    expect(summary.title, 'Mostly calm tonight');
    expect(
      summary.subtitle,
      'Two things could use a quick look. Everything else is fine.',
    );

    final calm = HomeSummary.from([_system('a', Severity.ok)], now: evening);
    expect(calm.title, 'All calm tonight');

    final critical = HomeSummary.from([
      _system('a', Severity.critical),
      _system('b', Severity.ok),
    ], now: evening);
    expect(critical.title, 'Needs you right now');

    final partial = HomeSummary.from([
      _system('a', Severity.ok),
      _system('b', Severity.unknown),
    ], now: evening);
    expect(partial.livePill, '1 of 2 live');
  });

  test('LPG status derives the progress fraction from ppm', () {
    final status = lpgStatus(_lpg(292, 'Warning'));
    expect(status.severity, Severity.warning);
    expect(status.value, '292');
    expect(status.progress, closeTo(0.292, 1e-9));
    expect(status.limitLabel, 'Safe limit 1000');
    expect(lpgStatus(_lpg(80, 'Safe')).severity, Severity.ok);
    expect(lpgStatus(_lpg(800, 'Critical')).severity, Severity.critical);
  });

  testWidgets('nav bar shows five labelled tabs and reports taps', (
    tester,
  ) async {
    int? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: ClayNavBar(
            selectedIndex: 0,
            onSelected: (i) => tapped = i,
            items: const [
              ClayNavItem('Home', Icons.home_outlined),
              ClayNavItem('LPG', Icons.local_fire_department_outlined),
              ClayNavItem('Pantry', Icons.inventory_2_outlined),
              ClayNavItem('Pest', Icons.track_changes_rounded),
              ClayNavItem('Child', Icons.sentiment_satisfied_outlined),
            ],
          ),
        ),
      ),
    );
    for (final label in ['Home', 'LPG', 'Pantry', 'Pest', 'Child']) {
      expect(find.text(label), findsOneWidget);
    }
    // Regression: the bar once stretched to the full screen height.
    expect(tester.getSize(find.byType(ClayNavBar)).height, lessThan(120));
    await tester.tap(find.text('Pest'));
    expect(tapped, 3);
  });
}
