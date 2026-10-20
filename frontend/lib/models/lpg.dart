double _double(Object? value) => (value as num).toDouble();

class LpgTelemetry {
  const LpgTelemetry({
    required this.schemaVersion,
    required this.deviceId,
    required this.ts,
    required this.seq,
    required this.ppmRaw,
    required this.tempC,
    required this.rhPct,
    required this.fanOn,
    required this.windowFrac,
    required this.edgeTier,
    required this.edgeOfflineMode,
  });

  factory LpgTelemetry.fromJson(Map<String, dynamic> json) => LpgTelemetry(
        schemaVersion: json['schema_version'] as int? ?? 1,
        deviceId: json['device_id'] as String,
        ts: DateTime.parse(json['ts'] as String),
        seq: json['seq'] as int,
        ppmRaw: _double(json['ppm_raw']),
        tempC: _double(json['temp_c']),
        rhPct: _double(json['rh_pct']),
        fanOn: json['fan_on'] as bool,
        windowFrac: _double(json['window_frac']),
        edgeTier: json['edge_tier'] as String,
        edgeOfflineMode: json['edge_offline_mode'] as bool,
      );

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        'device_id': deviceId,
        'ts': ts.toUtc().toIso8601String(),
        'seq': seq,
        'ppm_raw': ppmRaw,
        'temp_c': tempC,
        'rh_pct': rhPct,
        'fan_on': fanOn,
        'window_frac': windowFrac,
        'edge_tier': edgeTier,
        'edge_offline_mode': edgeOfflineMode,
      };

  final int schemaVersion;
  final String deviceId;
  final DateTime ts;
  final int seq;
  final double ppmRaw;
  final double tempC;
  final double rhPct;
  final bool fanOn;
  final double windowFrac;
  final String edgeTier;
  final bool edgeOfflineMode;
}

class LpgFeatures {
  const LpgFeatures({required this.ppmComp, required this.dPpm5s, required this.slope30s, required this.ma10, required this.ma30, required this.dRh10s, required this.tt700s});

  factory LpgFeatures.fromJson(Map<String, dynamic> json) => LpgFeatures(
        ppmComp: _double(json['ppm_comp']),
        dPpm5s: _double(json['d_ppm_5s']),
        slope30s: _double(json['slope_30s']),
        ma10: _double(json['ma10']),
        ma30: _double(json['ma30']),
        dRh10s: _double(json['d_rh_10s']),
        tt700s: _double(json['tt700_s']),
      );

  Map<String, dynamic> toJson() => {'ppm_comp': ppmComp, 'd_ppm_5s': dPpm5s, 'slope_30s': slope30s, 'ma10': ma10, 'ma30': ma30, 'd_rh_10s': dRh10s, 'tt700_s': tt700s};

  final double ppmComp, dPpm5s, slope30s, ma10, ma30, dRh10s, tt700s;
}

class LpgPrediction {
  const LpgPrediction({required this.cloudTier, required this.source, this.confidence});
  factory LpgPrediction.fromJson(Map<String, dynamic> json) => LpgPrediction(cloudTier: json['cloud_tier'] as String, source: json['source'] as String, confidence: (json['confidence'] as num?)?.toDouble());
  Map<String, dynamic> toJson() => {'cloud_tier': cloudTier, 'source': source, 'confidence': confidence};
  final String cloudTier, source;
  final double? confidence;
}

class LpgSnapshot {
  const LpgSnapshot({required this.raw, required this.features, required this.prediction});
  factory LpgSnapshot.fromJson(Map<String, dynamic> json) => LpgSnapshot(
        raw: LpgTelemetry.fromJson(Map<String, dynamic>.from(json['raw'] as Map)),
        features: LpgFeatures.fromJson(Map<String, dynamic>.from(json['features'] as Map)),
        prediction: LpgPrediction.fromJson(Map<String, dynamic>.from(json['prediction'] as Map)),
      );
  Map<String, dynamic> toJson() => {'raw': raw.toJson(), 'features': features.toJson(), 'prediction': prediction.toJson()};
  final LpgTelemetry raw;
  final LpgFeatures features;
  final LpgPrediction prediction;
}
