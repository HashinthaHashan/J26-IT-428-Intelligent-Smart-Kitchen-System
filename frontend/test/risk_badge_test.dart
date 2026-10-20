import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchenguard/core/theme.dart';
import 'package:kitchenguard/shared/widgets/risk_badge.dart';

void main() {
  final cases = <String, Color>{
    'Safe': safeGreen,
    'Fresh': safeGreen,
    'Warning': warningAmber,
    'Ripe': warningAmber,
    'Dangerous': dangerousOrange,
    'Deteriorating': dangerousOrange,
    'Danger': criticalRed,
    'Critical': criticalRed,
    'Spoiled': criticalRed,
    'info': safeGreen,
    'warning': warningAmber,
    'critical': criticalRed,
  };

  for (final entry in cases.entries) {
    testWidgets('RiskBadge maps ${entry.key} to its shared color', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: RiskBadge(status: entry.key))));
      final container = tester.widget<Container>(find.byKey(ValueKey('risk-badge-${entry.key}')));
      final decoration = container.decoration! as BoxDecoration;
      expect((decoration.border! as Border).top.color, entry.value);
      expect(find.text(entry.key), findsOneWidget);
    });
  }
}
