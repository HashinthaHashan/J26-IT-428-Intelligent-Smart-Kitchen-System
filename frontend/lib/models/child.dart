double _double(Object? value) => (value as num).toDouble();

class BoxDetection {
  const BoxDetection({required this.cls, required this.conf, required this.box});
  factory BoxDetection.fromJson(Map<String, dynamic> json) => BoxDetection(cls: json['cls'] as String, conf: _double(json['conf']), box: (json['box'] as List).map(_double).toList(growable: false));
  Map<String, dynamic> toJson() => {'cls': cls, 'conf': conf, 'box': box};
  final String cls;
  final double conf;
  final List<double> box;
}

class ChildEvent {
  const ChildEvent({required this.schemaVersion, required this.deviceId, required this.ts, required this.w, required this.h, required this.persons, required this.hazards, required this.poses});
  factory ChildEvent.fromJson(Map<String, dynamic> json) => ChildEvent(
        schemaVersion: json['schema_version'] as int? ?? 1, deviceId: json['device_id'] as String, ts: DateTime.parse(json['ts'] as String), w: json['w'] as int, h: json['h'] as int,
        persons: (json['persons'] as List).map((e) => BoxDetection.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        hazards: (json['hazards'] as List).map((e) => BoxDetection.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        poses: (json['poses'] as List).map((pose) => (pose as List).map((point) => (point as List).map(_double).toList(growable: false)).toList(growable: false)).toList(growable: false),
      );
  Map<String, dynamic> toJson() => {'schema_version': schemaVersion, 'device_id': deviceId, 'ts': ts.toUtc().toIso8601String(), 'w': w, 'h': h, 'persons': persons.map((e) => e.toJson()).toList(), 'hazards': hazards.map((e) => e.toJson()).toList(), 'poses': poses};
  final int schemaVersion, w, h;
  final String deviceId;
  final DateTime ts;
  final List<BoxDetection> persons, hazards;
  final List<List<List<double>>> poses;
}

class ChildRiskPrediction {
  const ChildRiskPrediction({required this.riskLevel, required this.dangerProb, required this.source});
  factory ChildRiskPrediction.fromJson(Map<String, dynamic> json) => ChildRiskPrediction(riskLevel: json['risk_level'] as String, dangerProb: _double(json['danger_prob']), source: json['source'] as String);
  Map<String, dynamic> toJson() => {'risk_level': riskLevel, 'danger_prob': dangerProb, 'source': source};
  final String riskLevel, source;
  final double dangerProb;
}

class ChildSnapshot {
  const ChildSnapshot({required this.event, required this.prediction});
  factory ChildSnapshot.fromJson(Map<String, dynamic> json) => ChildSnapshot(event: ChildEvent.fromJson(Map<String, dynamic>.from(json['event'] as Map)), prediction: ChildRiskPrediction.fromJson(Map<String, dynamic>.from(json['prediction'] as Map)));
  Map<String, dynamic> toJson() => {'event': event.toJson(), 'prediction': prediction.toJson()};
  final ChildEvent event;
  final ChildRiskPrediction prediction;
}
