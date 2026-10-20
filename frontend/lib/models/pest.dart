double _double(Object? value) => (value as num).toDouble();

class PestEvent {
  const PestEvent({required this.schemaVersion, required this.deviceId, required this.ts, required this.zone, required this.triggerSource, required this.pir, required this.vibRmsG, required this.vibTrigger, required this.ambientLux, required this.cameraInView, this.yoloPred, this.yoloConf});
  factory PestEvent.fromJson(Map<String, dynamic> json) => PestEvent(schemaVersion: json['schema_version'] as int? ?? 1, deviceId: json['device_id'] as String, ts: DateTime.parse(json['ts'] as String), zone: json['zone'] as String, triggerSource: json['trigger_source'] as String, pir: json['pir'] as bool, vibRmsG: _double(json['vib_rms_g']), vibTrigger: json['vib_trigger'] as bool, ambientLux: _double(json['ambient_lux']), cameraInView: json['camera_in_view'] as bool, yoloPred: json['yolo_pred'] as String?, yoloConf: (json['yolo_conf'] as num?)?.toDouble());
  Map<String, dynamic> toJson() => {'schema_version': schemaVersion, 'device_id': deviceId, 'ts': ts.toUtc().toIso8601String(), 'zone': zone, 'trigger_source': triggerSource, 'pir': pir, 'vib_rms_g': vibRmsG, 'vib_trigger': vibTrigger, 'ambient_lux': ambientLux, 'camera_in_view': cameraInView, 'yolo_pred': yoloPred, 'yolo_conf': yoloConf};
  final int schemaVersion;
  final String deviceId, zone, triggerSource;
  final DateTime ts;
  final bool pir, vibTrigger, cameraInView;
  final double vibRmsG, ambientLux;
  final String? yoloPred;
  final double? yoloConf;
}

class PestEventDocument {
  const PestEventDocument({required this.deviceId, required this.ts, required this.event});
  factory PestEventDocument.fromJson(Map<String, dynamic> json) => PestEventDocument(deviceId: json['device_id'] as String, ts: DateTime.parse(json['ts'] as String), event: PestEvent.fromJson(Map<String, dynamic>.from(json['event'] as Map)));
  Map<String, dynamic> toJson() => {'device_id': deviceId, 'ts': ts.toUtc().toIso8601String(), 'event': event.toJson()};
  final String deviceId;
  final DateTime ts;
  final PestEvent event;
}

class DeterrenceTrial {
  const DeterrenceTrial({required this.schemaVersion, required this.trialId, required this.deviceId, this.species, required this.condition, required this.zone, required this.activationS, required this.observationWindowS, required this.ts, this.exited, this.timeToLeaveS, this.systemVerdict, this.manualVerdict});
  factory DeterrenceTrial.fromJson(Map<String, dynamic> json) => DeterrenceTrial(schemaVersion: json['schema_version'] as int? ?? 1, trialId: json['trial_id'] as String, deviceId: json['device_id'] as String, species: json['species'] as String?, condition: json['condition'] as String, zone: json['zone'] as String, activationS: json['activation_s'] as int, observationWindowS: json['observation_window_s'] as int, exited: json['exited'] as bool?, timeToLeaveS: (json['time_to_leave_s'] as num?)?.toDouble(), systemVerdict: json['system_verdict'] as String?, manualVerdict: json['manual_verdict'] as String?, ts: DateTime.parse(json['ts'] as String));
  Map<String, dynamic> toJson() => {'schema_version': schemaVersion, 'trial_id': trialId, 'device_id': deviceId, 'species': species, 'condition': condition, 'zone': zone, 'activation_s': activationS, 'observation_window_s': observationWindowS, 'exited': exited, 'time_to_leave_s': timeToLeaveS, 'system_verdict': systemVerdict, 'manual_verdict': manualVerdict, 'ts': ts.toUtc().toIso8601String()};
  final int schemaVersion, activationS, observationWindowS;
  final String trialId, deviceId, condition, zone;
  /// null = unknown: the camera answered too late, never, or said non-pest. The deterrent never waits for it.
  final String? species;
  final bool? exited;
  final double? timeToLeaveS;
  final String? systemVerdict, manualVerdict;
  final DateTime ts;
}
