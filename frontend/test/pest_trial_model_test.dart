import 'package:flutter_test/flutter_test.dart';
import 'package:kitchenguard/models/pest.dart';

Map<String, dynamic> _trial({Object? species}) => {
  'schema_version': 1,
  'trial_id': 'pest-kitchen01-ABCD-0',
  'device_id': 'pest-kitchen01',
  'species': species,
  'condition': 'vibration_led',
  'zone': 'Sink',
  'activation_s': 15,
  'observation_window_s': 30,
  'exited': null,
  'time_to_leave_s': null,
  'system_verdict': 'uncertain',
  'ts': '2026-10-09T12:00:00Z',
};

void main() {
  test('a trial the camera never identified has no species', () {
    final t = DeterrenceTrial.fromJson(_trial());
    expect(t.species, isNull);
    expect(t.systemVerdict, 'uncertain');
  });

  test('a trial carries the species the camera attached while it ran', () {
    final t = DeterrenceTrial.fromJson(_trial(species: 'cockroach'));
    expect(t.species, 'cockroach');
    expect(DeterrenceTrial.fromJson(t.toJson()).species, 'cockroach');
    expect(t.toJson().containsKey('informed'), isFalse);
  });

  test('an IR trigger event parses', () {
    final e = PestEvent.fromJson({
      'schema_version': 1,
      'device_id': 'pest-kitchen01',
      'ts': '2026-10-09T12:00:00Z',
      'zone': 'Sink',
      'trigger_source': 'IR',
      'pir': false,
      'vib_rms_g': 0.0,
      'vib_trigger': false,
      'ambient_lux': 0.0,
      'camera_in_view': false,
      'yolo_pred': null,
      'yolo_conf': null,
    });
    expect(e.triggerSource, 'IR');
    expect(e.yoloPred, isNull);
  });
}
