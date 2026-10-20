import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/notification_service.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'core/ws_client.dart';
import 'models/alert.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: KitchenGuardApp()));
}

class KitchenGuardApp extends ConsumerStatefulWidget {
  const KitchenGuardApp({super.key});
  @override
  ConsumerState<KitchenGuardApp> createState() => _KitchenGuardAppState();
}

class _KitchenGuardAppState extends ConsumerState<KitchenGuardApp> {
  @override
  void initState() {
    super.initState();
    unawaited(
      Future<void>.microtask(
        () => ref.read(notificationServiceProvider).initialize(),
      ).catchError((Object _) {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<LiveFrame>>(liveFrameProvider, (_, next) {
      next.whenData((frame) {
        if (frame.type != 'alert') return;
        try {
          final alert = KitchenAlert.fromJson(frame.data);
          if ((alert.severity == 'danger' || alert.severity == 'critical') &&
              ref.read(notificationThrottleProvider).shouldNotify(alert)) {
            unawaited(
              ref
                  .read(notificationServiceProvider)
                  .showAlert(alert)
                  .catchError((Object _) {}),
            );
          }
        } catch (_) {
          // Invalid live data must not interrupt the application shell.
        }
      });
    });
    return MaterialApp.router(
      title: 'KitchenGuard',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
