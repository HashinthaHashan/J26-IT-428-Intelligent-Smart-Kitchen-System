import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../core/ws_client.dart';
import '../../models/pantry.dart';

class PantryController extends AsyncNotifier<PantrySnapshot> {
  PantryController(this.compartment);

  final String compartment;
  StreamSubscription<LiveFrame>? _subscription;

  String get _deviceId => compartment == 'banana'
      ? AppConfig.pantryBananaDeviceId
      : AppConfig.pantryPotatoDeviceId;

  @override
  Future<PantrySnapshot> build() async {
    _subscription = ref.read(wsClientProvider).events.listen(_onFrame);
    ref.onDispose(() => _subscription?.cancel());
    return _fetch();
  }

  Future<PantrySnapshot> _fetch() async {
    final dio = ref.read(dioProvider);
    return apiCall(() async {
      final response = await dio.get<Map<String, dynamic>>(
        '/api/pantry/$_deviceId/latest',
        queryParameters: {'compartment': compartment},
      );
      return PantrySnapshot.fromJson(response.data!);
    });
  }

  Future<void> refresh() async => state = await AsyncValue.guard(_fetch);

  void _onFrame(LiveFrame frame) {
    if (frame.type != 'pantry' || frame.data['device_id'] != _deviceId) return;
    try {
      final snapshot = PantrySnapshot.fromJson(frame.data);
      if (snapshot.raw.compartment == compartment) state = AsyncData(snapshot);
    } catch (_) {
      // Retain the last valid state when a malformed live frame arrives.
    }
  }
}

final bananaPantryProvider =
    AsyncNotifierProvider<PantryController, PantrySnapshot>(
  () => PantryController('banana'),
);

final potatoPantryProvider =
    AsyncNotifierProvider<PantryController, PantrySnapshot>(
  () => PantryController('potato'),
);

/// The last 24 h of readings for one compartment, oldest first, for the sensor
/// history chart. Fetched on demand when a sensor tile is tapped.
final pantryHistoryProvider = FutureProvider.autoDispose
    .family<List<PantrySnapshot>, String>((ref, compartment) async {
      final dio = ref.read(dioProvider);
      final deviceId =
          compartment == 'banana'
              ? AppConfig.pantryBananaDeviceId
              : AppConfig.pantryPotatoDeviceId;
      return apiCall(() async {
        final response = await dio.get<List<dynamic>>(
          '/api/pantry/$deviceId/history',
          queryParameters: {
            'compartment': compartment,
            'minutes': 1440,
            'limit': 1500,
          },
        );
        return (response.data ?? const <dynamic>[])
            .map(
              (item) => PantrySnapshot.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList()
          ..sort((a, b) => a.raw.ts.compareTo(b.raw.ts));
      });
    });
