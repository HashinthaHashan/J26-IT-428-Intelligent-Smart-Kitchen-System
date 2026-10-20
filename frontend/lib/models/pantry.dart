double _double(Object? value) => (value as num).toDouble();

class PantryTelemetry {
  const PantryTelemetry({required this.schemaVersion, required this.deviceId, required this.compartment, required this.ts, required this.mq3Ppm, required this.mq135Ppm, required this.tempC, required this.rhPct, this.massKg, this.itemCount, this.hueMean, this.brownPct, this.greenPct});
  factory PantryTelemetry.fromJson(Map<String, dynamic> json) => PantryTelemetry(
        schemaVersion: json['schema_version'] as int? ?? 1,
        deviceId: json['device_id'] as String,
        compartment: json['compartment'] as String,
        ts: DateTime.parse(json['ts'] as String),
        mq3Ppm: _double(json['mq3_ppm']), mq135Ppm: _double(json['mq135_ppm']),
        tempC: _double(json['temp_c']), rhPct: _double(json['rh_pct']),
        massKg: (json['mass_kg'] as num?)?.toDouble(), itemCount: json['item_count'] as int?,
        hueMean: (json['hue_mean'] as num?)?.toDouble(), brownPct: (json['brown_pct'] as num?)?.toDouble(), greenPct: (json['green_pct'] as num?)?.toDouble(),
      );
  Map<String, dynamic> toJson() => {'schema_version': schemaVersion, 'device_id': deviceId, 'compartment': compartment, 'ts': ts.toUtc().toIso8601String(), 'mq3_ppm': mq3Ppm, 'mq135_ppm': mq135Ppm, 'temp_c': tempC, 'rh_pct': rhPct, 'mass_kg': massKg, 'item_count': itemCount, 'hue_mean': hueMean, 'brown_pct': brownPct, 'green_pct': greenPct};
  final int schemaVersion;
  final String deviceId, compartment;
  final DateTime ts;
  final double mq3Ppm, mq135Ppm, tempC, rhPct;
  final double? massKg, hueMean, brownPct, greenPct;
  final int? itemCount;
}

class PantryPrediction {
  const PantryPrediction({required this.freshnessScore, required this.rslH, required this.stage, required this.source});
  factory PantryPrediction.fromJson(Map<String, dynamic> json) => PantryPrediction(freshnessScore: _double(json['freshness_score']), rslH: _double(json['rsl_h']), stage: json['stage'] as String, source: json['source'] as String);
  Map<String, dynamic> toJson() => {'freshness_score': freshnessScore, 'rsl_h': rslH, 'stage': stage, 'source': source};
  final double freshnessScore, rslH;
  final String stage, source;
}

class PantrySnapshot {
  const PantrySnapshot({required this.raw, required this.prediction});
  factory PantrySnapshot.fromJson(Map<String, dynamic> json) => PantrySnapshot(raw: PantryTelemetry.fromJson(Map<String, dynamic>.from(json['raw'] as Map)), prediction: PantryPrediction.fromJson(Map<String, dynamic>.from(json['prediction'] as Map)));
  Map<String, dynamic> toJson() => {'raw': raw.toJson(), 'prediction': prediction.toJson()};
  final PantryTelemetry raw;
  final PantryPrediction prediction;
}
