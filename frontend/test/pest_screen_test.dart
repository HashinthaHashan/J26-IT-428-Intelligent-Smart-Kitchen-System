import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchenguard/core/api_client.dart';
import 'package:kitchenguard/core/ws_client.dart';
import 'package:kitchenguard/features/pest/pest_screen.dart';
import 'package:kitchenguard/features/pest/pest_summary.dart';
import 'package:kitchenguard/models/pest.dart';

Map<String, dynamic> _event(
  DateTime ts, {
  required String zone,
  required String source,
  String? pred,
  double? conf,
}) => {
  'schema_version': 1,
  'device_id': 'pest-kitchen01',
  'ts': ts.toUtc().toIso8601String(),
  'zone': zone,
  'trigger_source': source,
  'pir': source == 'PIR',
  'vib_rms_g': 0.1,
  'vib_trigger': false,
  'ambient_lux': 120.0,
  'camera_in_view': source == 'Camera',
  'yolo_pred': pred,
  'yolo_conf': conf,
};

Map<String, dynamic> _doc(Map<String, dynamic> event) => {
  'device_id': 'pest-kitchen01',
  'ts': event['ts'],
  'event': event,
};

void main() {
  final now = DateTime.now();

  group('PestSummary', () {
    final events = [
      for (final e in [
        _event(
          now,
          zone: 'Sink',
          source: 'Camera',
          pred: 'cockroach',
          conf: 0.64,
        ),
        _event(
          now,
          zone: 'Trash bin',
          source: 'Camera',
          pred: 'cockroach',
          conf: 0.92,
        ),
        _event(now, zone: 'Trash bin', source: 'PIR', pred: 'none', conf: 0.3),
        _event(
          now.subtract(const Duration(days: 2)),
          zone: 'Sink',
          source: 'Camera',
          pred: 'cockroach',
          conf: 0.99,
        ),
      ])
        PestEvent.fromJson(e),
    ];

    test('counts only today and recalculates from the given events', () {
      final s = PestSummary.from(events, zone: 'All zones', allZones: true);
      expect(s.headline, '2 cockroach sightings today');
      expect(s.cockroachCount, 2);
      expect(s.otherCount, 1);
      expect(s.topMatchPct, 92); // the 99% one is two days old
      expect(s.zoneLabel, 'all zones');
      expect(s.subtitle, 'Camera caught the most. Check the sink first.');
    });

    test('no pests today reads as calm', () {
      final s = PestSummary.from(
        [events[2]],
        zone: 'Trash bin',
        allZones: false,
      );
      expect(s.headline, 'No pests spotted');
      expect(s.topMatchPct, isNull);
      expect(s.zoneLabel, 'trash bin');
    });

    test('singular wording and rat handling', () {
      final rat = PestEvent.fromJson(
        _event(now, zone: 'Sink', source: 'Camera', pred: 'rat', conf: 0.8),
      );
      expect(
        PestSummary.from([rat], zone: 'All zones', allZones: true).headline,
        '1 rat sighting today',
      );
      expect(
        PestSummary.from(
          [rat, events[0]],
          zone: 'All zones',
          allZones: true,
        ).headline,
        '2 pest sightings today',
      );
    });

    test('results map to labels', () {
      expect(resultOf(events[0]), PestResult.cockroach);
      expect(resultOf(events[2]), PestResult.none);
      expect(PestResult.none.label, isNull);
      expect(PestResult.nonPest.label, 'non-pest');
    });
  });

  testWidgets('zone chips filter the list and recalculate the summary', (
    tester,
  ) async {
    var deviceOnline = true;
    final docs = [
      _doc(
        _event(
          now,
          zone: 'Sink',
          source: 'Camera',
          pred: 'cockroach',
          conf: 0.64,
        ),
      ),
      _doc(
        _event(
          now.subtract(const Duration(minutes: 1)),
          zone: 'Trash bin',
          source: 'Camera',
          pred: 'cockroach',
          conf: 0.79,
        ),
      ),
      _doc(
        _event(
          now.subtract(const Duration(minutes: 2)),
          zone: 'Trash bin',
          source: 'PIR',
          pred: 'non_pest',
          conf: 0.3,
        ),
      ),
    ];
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final Object data;
            if (options.path == '/api/devices') {
              data = [
                {
                  'device_id': 'pest-kitchen01',
                  'component': 'pest',
                  'status': deviceOnline ? 'online' : 'offline',
                  'last_seen': DateTime.now().toUtc().toIso8601String(),
                  'meta': <String, dynamic>{},
                },
              ];
            } else {
              data = options.path.contains('/events') ? docs : <dynamic>[];
            }
            handler.resolve(
              Response(requestOptions: options, statusCode: 200, data: data),
            );
          },
        ),
      );
    final ws = WsClient(uri: Uri.parse('ws://unused'));
    await tester.binding.setSurfaceSize(const Size(430, 1600));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(dio),
          wsClientProvider.overrideWithValue(ws),
        ],
        child: const MaterialApp(home: Scaffold(body: PestScreen())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('2 cockroach sightings today'), findsOneWidget);
    expect(find.text('Monitoring all zones'), findsOneWidget);
    expect(find.text('Detection history'), findsOneWidget);

    // Filter to a zone with events: counts and wording recalculate.
    await tester.tap(find.text('Sink').first);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1 cockroach sighting today'), findsOneWidget);
    expect(find.text('Monitoring sink'), findsOneWidget);

    // Filter to a zone with none: calm summary plus an empty-state message.
    await tester.ensureVisible(find.text('Behind fridge'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Behind fridge'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('No pests spotted'), findsOneWidget);
    expect(find.text('No events in Behind fridge yet'), findsOneWidget);

    // Presence is polled as a safety net around WebSocket reconnects. Old
    // events disappear behind a clear offline state, then return on power-up.
    deviceOnline = false;
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('Pest device is offline'), findsOneWidget);
    expect(find.text('Detection history'), findsNothing);

    deviceOnline = true;
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Detection history'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    await ws.dispose();
    await tester.binding.setSurfaceSize(null);
  });
}
