import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchenguard/core/api_client.dart';
import 'package:kitchenguard/core/ws_client.dart';
import 'package:kitchenguard/features/pantry/pantry_screen.dart';
import 'package:kitchenguard/features/pantry/pantry_view.dart';

Map<String, dynamic> _doc(
  String compartment, {
  required double score,
  required String stage,
  required double rslH,
  double mq3 = 0.3,
}) => {
  'device_id': 'pantry01',
  'compartment': compartment,
  'ts': DateTime.now().toUtc().toIso8601String(),
  'raw': {
    'schema_version': 1,
    'device_id': 'pantry01',
    'compartment': compartment,
    'ts': DateTime.now().toUtc().toIso8601String(),
    'mq3_ppm': mq3,
    'mq135_ppm': 1.9,
    'temp_c': 30.1,
    'rh_pct': 62.0,
    'mass_kg': null,
    'item_count': null,
    'hue_mean': null,
    'brown_pct': null,
    'green_pct': null,
  },
  'prediction': {
    'freshness_score': score,
    'rsl_h': rslH,
    'stage': stage,
    'source': 'rule_fallback',
  },
};

void main() {
  group('presentation helpers', () {
    test('shelf life reads like 6d 21h', () {
      expect(formatShelfLife(165.0), '6d 21h');
      expect(formatShelfLife(168), '7d 0h');
      expect(formatShelfLife(21.5), '21h 30m');
      expect(formatShelfLife(5), '5h');
      expect(formatShelfLife(0.4), 'under 1h');
      expect(formatShelfLife(0), '0h');
    });

    test('stages map to a word, never colour alone', () {
      expect(stageView('Fresh').word, 'Fresh');
      expect(stageView('Ripe').word, 'Aging');
      expect(stageView('Deteriorating').word, 'Spoiling');
      expect(stageView('Spoiled').word, 'Spoiled');
      expect(stageView('???').word, 'Fresh'); // unknown stays calm, never crashes
    });

    test('ppm keeps one decimal when small', () {
      expect(formatPpm(0.34), '0.3');
      expect(formatPpm(1.94), '1.9');
      expect(formatPpm(112.6), '113');
    });
  });

  testWidgets(
    'shows the selected crop, swaps data on the switch, and opens sensor history',
    (tester) async {
      final requests = <String>[];
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requests.add('${options.path} ${options.queryParameters}');
              Object data;
              if (options.path.endsWith('/history') ||
                  options.path.contains('/api/alerts')) {
                data = <dynamic>[];
              } else if (options.queryParameters['compartment'] == 'potato') {
                data = _doc('potato', score: 55, stage: 'Ripe', rslH: 92, mq3: 70);
              } else {
                data = _doc('banana', score: 98, stage: 'Fresh', rslH: 165);
              }
              handler.resolve(
                Response(requestOptions: options, statusCode: 200, data: data),
              );
            },
          ),
        );
      final ws = WsClient(uri: Uri.parse('ws://unused'));
      await tester.binding.setSurfaceSize(const Size(430, 1200));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dioProvider.overrideWithValue(dio),
            wsClientProvider.overrideWithValue(ws),
          ],
          child: const MaterialApp(home: Scaffold(body: PantryScreen())),
        ),
      );
      await tester.pumpAndSettle();

      // Banana: fresh, 98 %, 6d 21h, four sensor tiles.
      expect(find.text('Pantry'), findsOneWidget);
      expect(find.text('Fresh'), findsOneWidget);
      expect(find.text('98%'), findsOneWidget);
      expect(find.text('6d 21h'), findsOneWidget);
      expect(find.text('MQ-3'), findsOneWidget);
      expect(find.text('MQ-135'), findsOneWidget);
      expect(find.text('Temperature'), findsOneWidget);
      expect(find.text('Humidity'), findsOneWidget);
      expect(find.text('0.3'), findsOneWidget);

      // Switch to potato: ripe -> "Aging", different numbers.
      await tester.tap(find.text('Potato'));
      await tester.pumpAndSettle();
      expect(find.text('Aging'), findsOneWidget);
      expect(find.text('55%'), findsOneWidget);
      expect(find.text('3d 20h'), findsOneWidget);
      expect(find.text('70.0'), findsOneWidget);
      expect(requests.any((r) => r.contains('compartment: potato')), isTrue);

      // Tapping a sensor opens its history for the selected crop.
      await tester.tap(find.text('MQ-3'));
      await tester.pumpAndSettle();
      expect(find.text('MQ-3 history'), findsOneWidget);
      expect(find.text('Potato box, last 24 hours'), findsOneWidget);
      expect(
        requests.any((r) => r.contains('/history') && r.contains('potato')),
        isTrue,
      );

      await tester.pumpWidget(const SizedBox());
      await ws.dispose();
      await tester.binding.setSurfaceSize(null);
    },
  );
}
