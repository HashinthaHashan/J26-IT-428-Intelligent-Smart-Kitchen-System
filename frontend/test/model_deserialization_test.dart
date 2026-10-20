import 'package:flutter_test/flutter_test.dart';
import 'package:kitchenguard/models/alert.dart';
import 'package:kitchenguard/models/child.dart';
import 'package:kitchenguard/models/device.dart';
import 'package:kitchenguard/models/lpg.dart';
import 'package:kitchenguard/models/pantry.dart';
import 'package:kitchenguard/models/pest.dart';

const ts = '2026-10-04T04:30:00Z';

void main() {
  test('Device parses every backend field', () {
    final model = Device.fromJson({'device_id': 'lpg01', 'component': 'lpg', 'status': 'online', 'last_seen': ts, 'meta': {'room': 'kitchen'}});
    expect(model.deviceId, 'lpg01');
    expect(model.component, 'lpg');
    expect(model.status, 'online');
    expect(model.lastSeen.isUtc, true);
    expect(model.meta['room'], 'kitchen');
  });

  test('LPG snapshot parses telemetry, all 7 feature fields and prediction', () {
    final model = LpgSnapshot.fromJson(_lpgJson(fanOn: false));
    expect(model.raw.schemaVersion, 1);
    expect(model.raw.seq, 42);
    expect(model.raw.tempC, 29.4);
    expect(model.raw.rhPct, 71.0);
    expect(model.raw.windowFrac, 0.5);
    expect(model.features.ppmComp, 204.5);
    expect(model.features.dPpm5s, 12.0);
    expect(model.features.slope30s, 1.4);
    expect(model.features.ma10, 190.0);
    expect(model.features.ma30, 170.0);
    expect(model.features.dRh10s, -0.5);
    expect(model.features.tt700s, 354.0);
    expect(model.prediction.cloudTier, 'Warning');
    expect(model.prediction.source, 'rule_fallback');
    expect(model.prediction.confidence, 0.72);
  });

  test('Pantry snapshot parses optional sensor and prediction fields', () {
    final model = PantrySnapshot.fromJson({'raw': {'schema_version': 1, 'device_id': 'pantry-banana01', 'compartment': 'banana', 'ts': ts, 'mq3_ppm': 34.2, 'mq135_ppm': 51.5, 'temp_c': 24.5, 'rh_pct': 68.0, 'mass_kg': 1.2, 'item_count': 6, 'hue_mean': 48.0, 'brown_pct': 12.0, 'green_pct': 55.0}, 'prediction': {'freshness_score': 78.0, 'rsl_h': 52.5, 'stage': 'Ripe', 'source': 'rule_fallback'}});
    expect(model.raw.compartment, 'banana');
    expect(model.raw.massKg, 1.2);
    expect(model.raw.itemCount, 6);
    expect(model.raw.hueMean, 48.0);
    expect(model.raw.brownPct, 12.0);
    expect(model.raw.greenPct, 55.0);
    expect(model.prediction.freshnessScore, 78.0);
    expect(model.prediction.rslH, 52.5);
    expect(model.prediction.stage, 'Ripe');
  });

  test('Pest event document parses all event fields', () {
    final model = PestEventDocument.fromJson({'device_id': 'pest-kitchen01', 'ts': ts, 'event': _pestEventJson()});
    expect(model.event.zone, 'Trash bin');
    expect(model.event.triggerSource, 'Camera');
    expect(model.event.pir, true);
    expect(model.event.vibRmsG, 0.31);
    expect(model.event.vibTrigger, false);
    expect(model.event.ambientLux, 8.0);
    expect(model.event.cameraInView, true);
    expect(model.event.yoloPred, 'cockroach');
    expect(model.event.yoloConf, 0.91);
  });

  test('Deterrence trial parses nullable verdict fields', () {
    final model = DeterrenceTrial.fromJson({'schema_version': 1, 'trial_id': 'trial-1', 'device_id': 'pest-kitchen01', 'species': 'rat', 'condition': 'ultrasonic_only', 'zone': 'Sink', 'activation_s': 20, 'observation_window_s': 120, 'exited': null, 'time_to_leave_s': null, 'system_verdict': 'uncertain', 'manual_verdict': null, 'ts': ts});
    expect(model.trialId, 'trial-1');
    expect(model.activationS, 20);
    expect(model.observationWindowS, 120);
    expect(model.exited, isNull);
    expect(model.systemVerdict, 'uncertain');
    expect(model.manualVerdict, isNull);
  });

  test('Child snapshot parses boxes and all 17 pose keypoints', () {
    final pose = List.generate(17, (index) => [0.2 + index / 100, 0.3 + index / 100, 0.8]);
    final model = ChildSnapshot.fromJson({'event': {'schema_version': 1, 'device_id': 'child-cam01', 'ts': ts, 'w': 1280, 'h': 720, 'persons': [{'cls': 'child', 'conf': 0.93, 'box': [0.1, 0.2, 0.4, 0.9]}], 'hazards': [{'cls': 'knife', 'conf': 0.88, 'box': [0.5, 0.4, 0.7, 0.6]}], 'poses': [pose]}, 'prediction': {'risk_level': 'Danger', 'danger_prob': 0.89, 'source': 'rule_fallback'}});
    expect(model.event.w, 1280);
    expect(model.event.h, 720);
    expect(model.event.persons.single.cls, 'child');
    expect(model.event.hazards.single.cls, 'knife');
    expect(model.event.poses.single.length, 17);
    expect(model.prediction.riskLevel, 'Danger');
    expect(model.prediction.dangerProb, 0.89);
  });

  test('Alert parses arbitrary nested data and acknowledgement', () {
    final model = KitchenAlert.fromJson({'schema_version': 1, 'alert_id': 'alert-1', 'component': 'child', 'device_id': 'child-cam01', 'severity': 'critical', 'message': 'Child in danger zone', 'data': {'prediction': {'risk_level': 'Danger'}}, 'ts': ts, 'acknowledged': false});
    expect(model.alertId, 'alert-1');
    expect(model.component, 'child');
    expect(model.severity, 'critical');
    expect((model.data['prediction'] as Map)['risk_level'], 'Danger');
    expect(model.acknowledged, false);
  });
}

Map<String, dynamic> _lpgJson({required bool fanOn}) => {
      'raw': {'schema_version': 1, 'device_id': 'lpg01', 'ts': ts, 'seq': 42, 'ppm_raw': 201.0, 'temp_c': 29.4, 'rh_pct': 71.0, 'fan_on': fanOn, 'window_frac': 0.5, 'edge_tier': 'Warning', 'edge_offline_mode': false},
      'features': {'ppm_comp': 204.5, 'd_ppm_5s': 12.0, 'slope_30s': 1.4, 'ma10': 190.0, 'ma30': 170.0, 'd_rh_10s': -0.5, 'tt700_s': 354.0},
      'prediction': {'cloud_tier': 'Warning', 'source': 'rule_fallback', 'confidence': 0.72},
    };

Map<String, dynamic> _pestEventJson() => {'schema_version': 1, 'device_id': 'pest-kitchen01', 'ts': ts, 'zone': 'Trash bin', 'trigger_source': 'Camera', 'pir': true, 'vib_rms_g': 0.31, 'vib_trigger': false, 'ambient_lux': 8.0, 'camera_in_view': true, 'yolo_pred': 'cockroach', 'yolo_conf': 0.91};
