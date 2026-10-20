class AppConfig {
  const AppConfig._();

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static const apiToken = String.fromEnvironment(
    'API_TOKEN',
    defaultValue: 'dev-token',
  );

  static const lpgDeviceId = String.fromEnvironment(
    'LPG_DEVICE_ID',
    defaultValue: 'lpg01',
  );
  // One shared pantry box = ONE device_id; banana and potato are two
  // compartments of it (see firmware/Pantry_Sensor_Device).
  static const pantryBananaDeviceId = String.fromEnvironment(
    'PANTRY_BANANA_DEVICE_ID',
    defaultValue: 'pantry01',
  );
  static const pantryPotatoDeviceId = String.fromEnvironment(
    'PANTRY_POTATO_DEVICE_ID',
    defaultValue: 'pantry01',
  );
  static const pestDeviceId = String.fromEnvironment(
    'PEST_DEVICE_ID',
    defaultValue: 'pest-kitchen01',
  );
  static const childDeviceId = String.fromEnvironment(
    'CHILD_DEVICE_ID',
    defaultValue: 'child-cam01',
  );

  static Uri get liveUri {
    final uri = Uri.parse(apiBaseUrl);
    return uri.replace(
      scheme: uri.scheme == 'https' ? 'wss' : 'ws',
      path: '/ws/live',
      query: null,
      fragment: null,
    );
  }
}
