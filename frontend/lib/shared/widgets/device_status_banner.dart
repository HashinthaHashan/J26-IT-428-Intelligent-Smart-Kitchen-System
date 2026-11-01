import 'package:flutter/material.dart';

import 'clay.dart';

class DeviceOnlineBanner extends StatelessWidget {
  const DeviceOnlineBanner({super.key});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: ClayPill(
      label: 'Device online',
      background: Clay.okPillBg,
      foreground: Clay.okPillText,
    ),
  );
}
