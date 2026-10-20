class KitchenAlert {
  const KitchenAlert({required this.schemaVersion, required this.alertId, required this.component, required this.deviceId, required this.severity, required this.message, required this.data, required this.ts, required this.acknowledged});
  factory KitchenAlert.fromJson(Map<String, dynamic> json) => KitchenAlert(
        schemaVersion: json['schema_version'] as int? ?? 1, alertId: json['alert_id'] as String, component: json['component'] as String, deviceId: json['device_id'] as String, severity: json['severity'] as String, message: json['message'] as String, data: Map<String, dynamic>.from(json['data'] as Map? ?? const {}), ts: DateTime.parse(json['ts'] as String), acknowledged: json['acknowledged'] as bool? ?? false,
      );
  Map<String, dynamic> toJson() => {'schema_version': schemaVersion, 'alert_id': alertId, 'component': component, 'device_id': deviceId, 'severity': severity, 'message': message, 'data': data, 'ts': ts.toUtc().toIso8601String(), 'acknowledged': acknowledged};
  KitchenAlert copyWith({bool? acknowledged}) => KitchenAlert(schemaVersion: schemaVersion, alertId: alertId, component: component, deviceId: deviceId, severity: severity, message: message, data: data, ts: ts, acknowledged: acknowledged ?? this.acknowledged);
  final int schemaVersion;
  final String alertId, component, deviceId, severity, message;
  final Map<String, dynamic> data;
  final DateTime ts;
  final bool acknowledged;
}
