import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchenguard/core/api_client.dart';
import 'package:kitchenguard/core/ws_client.dart';
import 'package:kitchenguard/features/lpg/lpg_screen.dart';
import 'package:kitchenguard/shared/widgets/clay_toggle.dart';

const _ts = '2026-10-04T04:30:00Z';

void main() {
  testWidgets('fan toggle posts the command and displays refreshed state', (
    tester,
  ) async {
    var fanOn = false;
    Map<String, dynamic>? command;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.method == 'POST') {
              command = Map<String, dynamic>.from(options.data as Map);
              fanOn = true;
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {...command!, 'device_id': 'lpg01'},
                ),
              );
            }
            if (options.path.endsWith('/history')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: [_snapshot(fanOn)],
                ),
              );
            }
            return handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _snapshot(fanOn),
              ),
            );
          },
        ),
      );
    final ws = WsClient(uri: Uri.parse('ws://unused'));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(dio),
          wsClientProvider.overrideWithValue(ws),
        ],
        child: const MaterialApp(home: Scaffold(body: LpgScreen())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('fan-toggle')), 200);
    await tester.ensureVisible(find.byKey(const Key('fan-toggle')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ClayToggle>(find.byKey(const Key('fan-toggle'))).value,
      false,
    );

    await tester.tap(find.byKey(const Key('fan-toggle')));
    await tester.pumpAndSettle();

    expect(command, {'action': 'fan', 'value': 1});
    expect(
      tester.widget<ClayToggle>(find.byKey(const Key('fan-toggle'))).value,
      true,
    );
    expect(find.text('Exhaust fan command sent'), findsOneWidget);
    // Unmount first so the header's connection listener releases the socket.
    await tester.pumpWidget(const SizedBox());
    await ws.dispose();
  });
}

Map<String, dynamic> _snapshot(bool fanOn) => {
  'device_id': 'lpg01',
  'ts': _ts,
  'raw': {
    'schema_version': 1,
    'device_id': 'lpg01',
    'ts': _ts,
    'seq': 1,
    'ppm_raw': 100.0,
    'temp_c': 29.0,
    'rh_pct': 70.0,
    'fan_on': fanOn,
    'window_frac': 0.0,
    'edge_tier': 'Safe',
    'edge_offline_mode': false,
  },
  'features': {
    'ppm_comp': 100.0,
    'd_ppm_5s': 0.0,
    'slope_30s': 0.0,
    'ma10': 100.0,
    'ma30': 100.0,
    'd_rh_10s': 0.0,
    'tt700_s': 600.0,
  },
  'prediction': {
    'cloud_tier': 'Safe',
    'source': 'rule_fallback',
    'confidence': 1.0,
  },
};
