import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/alert.dart';

abstract interface class NotificationService {
  Future<void> initialize();
  Future<void> showAlert(KitchenAlert alert);
}

class LocalNotificationService implements NotificationService {
  LocalNotificationService(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<void> initialize() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(settings: settings);
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  @override
  Future<void> showAlert(KitchenAlert alert) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'critical_alerts',
        'Safety alerts',
        channelDescription: 'Danger and critical KitchenGuard alerts',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
    );
    await _plugin.show(
      // One slot per device: a newer alert replaces the old one instead of
      // stacking dozens of notifications in the shade.
      id: '${alert.component}/${alert.deviceId}'.hashCode & 0x7fffffff,
      title: 'KitchenGuard ${alert.severity}',
      body: alert.message,
      notificationDetails: details,
    );
  }
}

/// Decides whether a live alert deserves a phone notification. A device that
/// stays dangerous only notifies once per [cooldown]; escalating to a higher
/// severity always notifies.
class NotificationThrottle {
  NotificationThrottle({
    this.cooldown = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration cooldown;
  final DateTime Function() _clock;
  final _last = <String, (int, DateTime)>{};

  static const _rank = {'info': 0, 'warning': 1, 'danger': 2, 'critical': 3};

  bool shouldNotify(KitchenAlert alert) {
    final key = '${alert.component}/${alert.deviceId}';
    final rank = _rank[alert.severity] ?? 0;
    final now = _clock();
    final previous = _last[key];
    if (previous != null &&
        rank <= previous.$1 &&
        now.difference(previous.$2) < cooldown) {
      return false;
    }
    _last[key] = (rank, now);
    return true;
  }
}

final notificationThrottleProvider = Provider<NotificationThrottle>(
  (ref) => NotificationThrottle(),
);

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return LocalNotificationService(FlutterLocalNotificationsPlugin());
});

// TODO(Phase 5): Add an FCM implementation after Firebase project setup,
// google-services.json/GoogleService-Info.plist, and APNs credentials exist.
