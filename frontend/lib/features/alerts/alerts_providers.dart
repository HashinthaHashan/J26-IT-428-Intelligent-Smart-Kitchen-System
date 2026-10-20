import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/ws_client.dart';
import '../../models/alert.dart';

class AlertsState {
  const AlertsState({required this.alerts, required this.showAll});
  final List<KitchenAlert> alerts;
  final bool showAll;
  int get unreadCount => alerts.where((alert) => !alert.acknowledged).length;
  AlertsState copyWith({List<KitchenAlert>? alerts, bool? showAll}) => AlertsState(alerts: alerts ?? this.alerts, showAll: showAll ?? this.showAll);
}

class AlertsController extends AsyncNotifier<AlertsState> {
  StreamSubscription<LiveFrame>? _subscription;

  @override
  Future<AlertsState> build() async {
    _subscription = ref.read(wsClientProvider).events.listen(_onFrame);
    ref.onDispose(() => _subscription?.cancel());
    return _fetch(showAll: false);
  }

  Future<AlertsState> _fetch({required bool showAll}) async {
    final dio = ref.read(dioProvider);
    return apiCall(() async {
      final response = await dio.get<List<dynamic>>(
        '/api/alerts',
        queryParameters: showAll ? null : {'acknowledged': false},
      );
      return AlertsState(
        alerts: response.data!
            .map((item) => KitchenAlert.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList(),
        showAll: showAll,
      );
    });
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => _fetch(showAll: state.value?.showAll ?? false));
  }

  Future<void> setShowAll(bool showAll) async {
    state = await AsyncValue.guard(() => _fetch(showAll: showAll));
  }

  Future<void> acknowledge(KitchenAlert alert) async {
    final current = state.value;
    if (current == null) return;
    final optimistic = current.showAll
        ? current.alerts.map((item) => item.alertId == alert.alertId ? item.copyWith(acknowledged: true) : item).toList()
        : current.alerts.where((item) => item.alertId != alert.alertId).toList();
    state = AsyncData(current.copyWith(alerts: optimistic));
    try {
      final dio = ref.read(dioProvider);
      await apiCall(() => dio.post<Map<String, dynamic>>('/api/alerts/${alert.alertId}/ack'));
    } catch (_) {
      state = AsyncData(current);
      rethrow;
    }
  }

  void _onFrame(LiveFrame frame) {
    if (frame.type != 'alert') return;
    final current = state.value;
    if (current == null) return;
    try {
      final alert = KitchenAlert.fromJson(frame.data);
      state = AsyncData(current.copyWith(alerts: [alert, ...current.alerts]));
    } catch (_) {
      // Keep the inbox usable if one frame is malformed.
    }
  }
}

final alertsProvider = AsyncNotifierProvider<AlertsController, AlertsState>(AlertsController.new);
final unreadAlertsProvider = Provider<int>((ref) => ref.watch(alertsProvider).value?.unreadCount ?? 0);
