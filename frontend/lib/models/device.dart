class Device {
  const Device({
    required this.deviceId,
    required this.component,
    required this.status,
    required this.lastSeen,
    required this.meta,
  });

  factory Device.fromJson(Map<String, dynamic> json) => Device(
        deviceId: json['device_id'] as String,
        component: json['component'] as String,
        status: json['status'] as String? ?? 'unknown',
        lastSeen: DateTime.parse(json['last_seen'] as String),
        meta: Map<String, dynamic>.from(json['meta'] as Map? ?? const {}),
      );

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'component': component,
        'status': status,
        'last_seen': lastSeen.toUtc().toIso8601String(),
        'meta': meta,
      };

  final String deviceId;
  final String component;
  final String status;
  final DateTime lastSeen;
  final Map<String, dynamic> meta;
}
