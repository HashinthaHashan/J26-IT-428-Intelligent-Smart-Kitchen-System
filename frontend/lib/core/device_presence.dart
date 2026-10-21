import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import 'api_client.dart';
import 'config.dart';
import 'ws_client.dart';

enum DeviceAvailability { checking, online, offline }

const _pollInterval = Duration(seconds: 2);
const _expiryInterval = Duration(seconds: 1);
const _offlineAfter = Duration(seconds: 15);

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
  Timer? _expiryTimer;
  final Map<String, int> _onlineHeartbeats = {};
  final Set<String> _expiryEnabled = {};
  bool _disposed = false;

  @override
  Future<Map<String, Device>> build() async {
    _subscription = ref.read(wsClientProvider).events.listen(_onFrame);
    _pollTimer = Timer.periodic(_pollInterval, (_) => _refreshSilently());
    _expiryTimer = Timer.periodic(_expiryInterval, (_) => _expireStale());
    ref.onDispose(() {
      _disposed = true;
      _pollTimer?.cancel();
      _expiryTimer?.cancel();
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
        result[key] =
            _expiryEnabled.contains(key) ? _withFreshStatus(device) : device;
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
    if (frame.type != 'device_status') {
      _markLiveDataSeen(frame);
      return;
    }
    final component = frame.data['component'] as String?;
    final deviceId = frame.data['device_id'] as String?;
    if (component == null || deviceId == null) return;
    final key = _key(component, deviceId);
    final status = (frame.data['status'] as String? ?? 'offline').toLowerCase();
    if (status == 'online') {
      final count = (_onlineHeartbeats[key] ?? 0) + 1;
      _onlineHeartbeats[key] = count;
      if (count >= 2) _expiryEnabled.add(key);
    } else {
      _onlineHeartbeats.remove(key);
      _expiryEnabled.remove(key);
    }
    final current = {...(state.value ?? _offlineDefaults())};
    current[key] = Device(
      deviceId: deviceId,
      component: component,
      status: status,
      lastSeen:
          frame.data['last_seen'] == null
              ? DateTime.now().toUtc()
              : DateTime.parse(frame.data['last_seen'] as String),
      meta: const {},
    );
    state = AsyncData(current);
  }

  Device _withFreshStatus(Device device) {
    if (device.status.toLowerCase() != 'online' ||
        DateTime.now().toUtc().difference(device.lastSeen.toUtc()) <=
            _offlineAfter) {
      return device;
    }
    return Device(
      deviceId: device.deviceId,
      component: device.component,
      status: 'offline',
      lastSeen: device.lastSeen,
      meta: device.meta,
    );
  }

  void _markLiveDataSeen(LiveFrame frame) {
    const liveTypes = {'lpg', 'pantry', 'pest', 'child'};
    if (!liveTypes.contains(frame.type)) return;
    final deviceId = frame.data['device_id'] as String?;
    if (deviceId == null) return;
    final current = {...(state.value ?? _offlineDefaults())};
    final key = _key(frame.type, deviceId);
    current[key] = Device(
      deviceId: deviceId,
      component: frame.type,
      status: 'online',
      lastSeen: DateTime.now().toUtc(),
      meta: current[key]?.meta ?? const {},
    );
    state = AsyncData(current);
  }

  void _expireStale() {
    final devices = state.value;
    if (devices == null) return;
    var changed = false;
    final fresh = <String, Device>{};
    for (final entry in devices.entries) {
      final device =
          _expiryEnabled.contains(entry.key)
              ? _withFreshStatus(entry.value)
              : entry.value;
      fresh[entry.key] = device;
      changed |= device.status != entry.value.status;
    }
    if (changed) state = AsyncData(fresh);
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
