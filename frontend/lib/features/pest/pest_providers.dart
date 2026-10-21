import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../core/ws_client.dart';
import '../../models/pest.dart';

const _pageSize = 50;

/// The state of the pest events page.
class PestState {
  const PestState({
    required this.events,
    this.pendingTrials = const [],
    this.limit = _pageSize,
    this.loadingMore = false,
  });
  final List<PestEventDocument> events;
  final List<DeterrenceTrial> pendingTrials;

  /// How many events were asked of the backend (it pages by `limit` only).
  final int limit;
  final bool loadingMore;

  /// The backend returned a full page, so older events probably exist.
  bool get hasMore => events.length >= limit;

  PestState copyWith({
    List<PestEventDocument>? events,
    List<DeterrenceTrial>? pendingTrials,
    int? limit,
    bool? loadingMore,
  }) => PestState(
    events: events ?? this.events,
    pendingTrials: pendingTrials ?? this.pendingTrials,
    limit: limit ?? this.limit,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

class PestController extends AsyncNotifier<PestState> {
  StreamSubscription<LiveFrame>? _subscription;

  @override
  Future<PestState> build() async {
    _subscription = ref.read(wsClientProvider).events.listen(_onFrame);
    ref.onDispose(() => _subscription?.cancel());
    return _fetch();
  }

  Future<PestState> _fetch({int limit = _pageSize}) async {
    final dio = ref.read(dioProvider);
    return apiCall(() async {
      final response = await dio.get<List<dynamic>>(
        '/api/pest/${AppConfig.pestDeviceId}/events',
        queryParameters: {'limit': limit},
      );
      return PestState(
        events: response.data!
            .map(
              (item) => PestEventDocument.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(),
        limit: limit,
      );
    });
  }

  Future<void> refresh() async {
    final limit = state.value?.limit ?? _pageSize;
    final fresh = await AsyncValue.guard(() => _fetch(limit: limit));
    final pending = state.value?.pendingTrials ?? const <DeterrenceTrial>[];
    state = fresh.whenData((value) => value.copyWith(pendingTrials: pending));
  }

  /// Fetches the next page of older events (the API only supports `limit`).
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.loadingMore || !current.hasMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final next = await _fetch(limit: current.limit + _pageSize);
      final pending = state.value?.pendingTrials ?? current.pendingTrials;
      state = AsyncData(next.copyWith(pendingTrials: pending));
    } catch (_) {
      state = AsyncData(current.copyWith(loadingMore: false));
      rethrow;
    }
  }

  Future<void> review(DeterrenceTrial trial, String verdict) async {
    final dio = ref.read(dioProvider);
    await apiCall(
      () => dio.post<Map<String, dynamic>>(
        '/api/pest/${trial.deviceId}/trials/${trial.trialId}/review',
        data: {'manual_verdict': verdict},
      ),
    );
    final current = state.value;
    if (current != null) {
      state = AsyncData(
        current.copyWith(
          pendingTrials: current.pendingTrials
              .where((item) => item.trialId != trial.trialId)
              .toList(),
        ),
      );
    }
  }

  void _onFrame(LiveFrame frame) {
    final current = state.value;
    if (current == null || frame.data['device_id'] != AppConfig.pestDeviceId) {
      return;
    }
    try {
      if (frame.type == 'pest') {
        final event = PestEventDocument.fromJson(frame.data);
        state = AsyncData(
          current.copyWith(
            events: [event, ...current.events].take(current.limit).toList(),
          ),
        );
      } else if (frame.type == 'pest_update') {
        // The backend classified this event's photo: replace it in place (same
        // device, time and trigger sensor) instead of adding a duplicate row.
        final updated = PestEventDocument.fromJson(frame.data);
        bool same(PestEventDocument e) =>
            e.ts == updated.ts &&
            e.event.triggerSource == updated.event.triggerSource;
        state = AsyncData(
          current.copyWith(
            events: [for (final e in current.events) same(e) ? updated : e],
          ),
        );
      } else if (frame.type == 'deterrence_trial') {
        final trial = DeterrenceTrial.fromJson(frame.data);
        if (trial.systemVerdict != null && trial.manualVerdict == null) {
          state = AsyncData(
            current.copyWith(pendingTrials: [trial, ...current.pendingTrials]),
          );
        }
      }
    } catch (_) {
      // Preserve valid history on malformed live data.
    }
  }
}

final pestProvider = AsyncNotifierProvider<PestController, PestState>(
  PestController.new,
);
