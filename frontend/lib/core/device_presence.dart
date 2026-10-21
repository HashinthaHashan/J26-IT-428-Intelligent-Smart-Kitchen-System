import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import 'api_client.dart';
import 'config.dart';
import 'ws_client.dart';

enum DeviceAvailability { checking, online, offline }

typedef DeviceIdentity = ({String component, String deviceId});

String _key(String component, String deviceId) => '$component/$deviceId';

Map<String, Device> _offlineDefaults() {
  final never = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  Device offline(String component, String deviceId) => Device(
    deviceId: deviceId,
    component: component,
    status: 'offline',
    lastSeen: never,
    meta: const {},
  );
  final devices = [
    offline('lpg', AppConfig.lpgDeviceId),
    offline('pantry', AppConfig.pantryBananaDeviceId),
    offline('pest', AppConfig.pestDeviceId),
    offline('child', AppConfig.childDeviceId),
  ];
  return {for (final device in devices) _keyForDevice(device): device};
}

String _keyForDevice(Device device) => _key(device.component, device.deviceId);

class DevicePresenceController extends AsyncNotifier<Map<String, Device>> {
  StreamSubscription<LiveFrame>? _subscription;
  Timer? _pollTimer;
  bool _disposed = false;

  @override
  Future<Map<String, Device>> build() async {
    _subscription = ref.read(wsClientProvider).events.listen(_onFrame);
    _pollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshSilently(),
    );
    ref.onDispose(() {
      _disposed = true;
      _pollTimer?.cancel();
      _subscription?.cancel();
    });
    return _fetch();
  }

  Future<Map<String, Device>> _fetch() async {
    final response = await ref
        .read(dioProvider)
        .get<List<dynamic>>('/api/devices');
    final result = _offlineDefaults();
    for (final item in response.data ?? const <dynamic>[]) {
      final device = Device.fromJson(Map<String, dynamic>.from(item as Map));
      final key = _keyForDevice(device);
      final previous = result[key];
      if (previous == null || !device.lastSeen.isBefore(previous.lastSeen)) {
        result[key] = device;
      }
    }
    return result;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> _refreshSilently() async {
    try {
      final fresh = await _fetch();
      if (!_disposed) state = AsyncData(fresh);
    } catch (_) {
      // WebSocket status frames still update the UI during a short REST blip.
    }
  }

  void _onFrame(LiveFrame frame) {
    if (frame.type != 'device_status') return;
    final component = frame.data['component'] as String?;
    final deviceId = frame.data['device_id'] as String?;
    if (component == null || deviceId == null) return;
    final current = {...(state.value ?? _offlineDefaults())};
    current[_key(component, deviceId)] = Device(
      deviceId: deviceId,
      component: component,
      status: (frame.data['status'] as String? ?? 'offline').toLowerCase(),
      lastSeen:
          frame.data['last_seen'] == null
              ? DateTime.now().toUtc()
              : DateTime.parse(frame.data['last_seen'] as String),
      meta: const {},
    );
    state = AsyncData(current);
  }
}

final devicePresenceProvider =
    AsyncNotifierProvider<DevicePresenceController, Map<String, Device>>(
      DevicePresenceController.new,
    );

final deviceAvailabilityProvider =
    Provider.family<DeviceAvailability, DeviceIdentity>((ref, identity) {
      final presence = ref.watch(devicePresenceProvider);
      final devices = presence.value;
      if (devices == null) {
        return DeviceAvailability.checking;
      }
      final device = devices[_key(identity.component, identity.deviceId)];
      return device?.status.toLowerCase() == 'online'
          ? DeviceAvailability.online
          : DeviceAvailability.offline;
    });
