import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../core/ws_client.dart';
import '../../models/lpg.dart';

class LpgState {
  const LpgState({required this.latest, required this.history});

  final LpgSnapshot latest;
  final List<LpgSnapshot> history;

  LpgState copyWith({LpgSnapshot? latest, List<LpgSnapshot>? history}) =>
      LpgState(latest: latest ?? this.latest, history: history ?? this.history);
}

class LpgController extends AsyncNotifier<LpgState> {
  StreamSubscription<LiveFrame>? _subscription;

  @override
  Future<LpgState> build() async {
    _subscription = ref.read(wsClientProvider).events.listen(_onFrame);
    ref.onDispose(() => _subscription?.cancel());
    return _fetch();
  }

  Future<LpgState> _fetch() async {
    final dio = ref.read(dioProvider);
    return apiCall(() async {
      final responses = await Future.wait([
        dio.get<Map<String, dynamic>>(
          '/api/lpg/${AppConfig.lpgDeviceId}/latest',
        ),
        dio.get<List<dynamic>>(
          '/api/lpg/${AppConfig.lpgDeviceId}/history',
          queryParameters: {'minutes': 1440},
        ),
      ]);
      final latest = LpgSnapshot.fromJson(
        Map<String, dynamic>.from(responses[0].data! as Map),
      );
      final history =
          (responses[1].data! as List)
              .map(
                (item) => LpgSnapshot.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList()
            ..sort((a, b) => a.raw.ts.compareTo(b.raw.ts));
      return LpgState(latest: latest, history: history);
    });
  }

  Future<void> refresh() async {
    // No intermediate AsyncLoading: the last good value stays visible (Home
    // reads it too), matching the pantry/pest/child controllers.
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> setFan(bool enabled) => _sendCommand('fan', enabled ? 1 : 0);

  Future<void> setWindow(bool open) => _sendCommand('window', open ? 1 : 0);

  Future<void> _sendCommand(String action, num value) async {
    final dio = ref.read(dioProvider);
    await apiCall(
      () => dio.post<Map<String, dynamic>>(
        '/api/lpg/${AppConfig.lpgDeviceId}/cmd',
        data: {'action': action, 'value': value},
      ),
    );
    final refreshed = await _fetch();
    state = AsyncData(refreshed);
  }

  void _onFrame(LiveFrame frame) {
    if (frame.type != 'lpg' ||
        frame.data['device_id'] != AppConfig.lpgDeviceId) {
      return;
    }
    try {
      final snapshot = LpgSnapshot.fromJson(frame.data);
      final current = state.value;
      if (current == null) {
        state = AsyncData(LpgState(latest: snapshot, history: [snapshot]));
        return;
      }
      // Frames arrive in order, so append instead of re-sorting a day of
      // samples on every frame; only sort if one arrives late.
      final previous = current.history;
      final inOrder =
          previous.isEmpty || !snapshot.raw.ts.isBefore(previous.last.raw.ts);
      var history = [...previous, snapshot];
      if (!inOrder) history.sort((a, b) => a.raw.ts.compareTo(b.raw.ts));
      final cutoff = DateTime.now().subtract(const Duration(hours: 24));
      final firstKept = history.indexWhere((e) => e.raw.ts.isAfter(cutoff));
      history = firstKept <= 0 ? history : history.sublist(firstKept);
      state = AsyncData(current.copyWith(latest: snapshot, history: history));
    } catch (_) {
      // A malformed live frame must not discard the last valid REST state.
    }
  }
}

final lpgProvider = AsyncNotifierProvider<LpgController, LpgState>(
  LpgController.new,
);
