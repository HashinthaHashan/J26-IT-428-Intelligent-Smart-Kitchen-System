import 'package:flutter_test/flutter_test.dart';
import 'package:kitchenguard/core/notification_service.dart';
import 'package:kitchenguard/models/alert.dart';

KitchenAlert _alert(String severity) => KitchenAlert.fromJson({
  'schema_version': 1,
  'alert_id': 'a-$severity',
  'component': 'lpg',
  'device_id': 'lpg01',
  'severity': severity,
  'message': 'LPG',
  'data': <String, dynamic>{},
  'ts': '2026-10-04T04:30:00Z',
  'acknowledged': false,
});

void main() {
  test('repeats are muted during the cooldown, escalation is not', () {
    var now = DateTime(2026, 10, 7, 12);
    final throttle = NotificationThrottle(clock: () => now);

    expect(throttle.shouldNotify(_alert('danger')), isTrue);
    for (var i = 0; i < 20; i++) {
      now = now.add(const Duration(seconds: 2));
      expect(throttle.shouldNotify(_alert('danger')), isFalse);
    }
    expect(throttle.shouldNotify(_alert('critical')), isTrue);

    now = now.add(const Duration(minutes: 6));
    expect(throttle.shouldNotify(_alert('critical')), isTrue);
  });
}
