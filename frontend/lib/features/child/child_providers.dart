import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../core/ws_client.dart';
import '../../models/child.dart';

class ChildState {
  const ChildState({required this.snapshot, this.why});
  final ChildSnapshot snapshot;
  final String? why;
  ChildState copyWith({ChildSnapshot? snapshot, String? why}) => ChildState(snapshot: snapshot ?? this.snapshot, why: why ?? this.why);
}

class ChildController extends AsyncNotifier<ChildState> {
  StreamSubscription<LiveFrame>? _subscription;
  @override
  Future<ChildState> build() async {
    _subscription = ref.read(wsClientProvider).events.listen(_onFrame);
    ref.onDispose(() => _subscription?.cancel());
    return _fetch();
  }

  Future<ChildState> _fetch() async {
    final dio = ref.read(dioProvider);
    return apiCall(() async {
      final response = await dio.get<Map<String, dynamic>>('/api/child/${AppConfig.childDeviceId}/latest');
      final snapshot = ChildSnapshot.fromJson(response.data!);
      return ChildState(snapshot: snapshot, why: _whyFrom(snapshot.event));
    });
  }

  Future<void> refresh() async => state = await AsyncValue.guard(_fetch);

  void _onFrame(LiveFrame frame) {
    if (frame.data['device_id'] != AppConfig.childDeviceId) return;
    try {
      if (frame.type == 'child') {
        final snapshot = ChildSnapshot.fromJson(frame.data);
        state = AsyncData(ChildState(snapshot: snapshot, why: _whyFrom(snapshot.event)));
      } else if (frame.type == 'alert' && frame.data['component'] == 'child') {
        final current = state.value;
        if (current == null) return;
        final data = Map<String, dynamic>.from(frame.data['data'] as Map? ?? const {});
        final eventJson = data['event'];
        if (eventJson is Map) {
          state = AsyncData(current.copyWith(why: _whyFrom(ChildEvent.fromJson(Map<String, dynamic>.from(eventJson)))));
        }
      }
    } catch (_) {
      // Keep the last coherent risk view.
    }
  }

  static String? _whyFrom(ChildEvent event) {
    if (event.hazards.isEmpty) return null;
    return 'Near ${event.hazards.first.cls.replaceAll('_', ' ')}';
  }
}

final childProvider = AsyncNotifierProvider<ChildController, ChildState>(ChildController.new);
