import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/api_client.dart';
import '../../models/alert.dart';
import '../../shared/widgets/loading_error_view.dart';
import '../../shared/widgets/calm_surface.dart';
import 'alerts_providers.dart';

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(alertsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: value.when(
        loading: () => const LoadingErrorView.loading(),
        error:
            (error, _) => LoadingErrorView.error(
              message: userFacingError(error),
              onRetry: () => ref.read(alertsProvider.notifier).refresh(),
            ),
        data:
            (data) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: CalmSurface(
                    padding: EdgeInsets.zero,
                    child: SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 3,
                      ),
                      title: const Text('Show acknowledged'),
                      subtitle: const Text('Include resolved notifications'),
                      secondary: const SoftIcon(
                        Icons.done_all_outlined,
                        size: 42,
                      ),
                      value: data.showAll,
                      onChanged: ref.read(alertsProvider.notifier).setShowAll,
                    ),
                  ),
                ),
                Expanded(
                  child:
                      data.alerts.isEmpty
                          ? const LoadingErrorView.empty(
                            emptyTitle: 'No alerts to show',
                            emptyIcon: Icons.notifications_none,
                          )
                          : RefreshIndicator(
                            onRefresh:
                                ref.read(alertsProvider.notifier).refresh,
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                              itemCount: data.alerts.length,
                              itemBuilder:
                                  (context, index) => _AlertRow(
                                    alert: data.alerts[index],
                                    onAck:
                                        () => _ack(
                                          context,
                                          ref,
                                          data.alerts[index],
                                        ),
                                  ),
                            ),
                          ),
                ),
              ],
            ),
      ),
    );
  }

  Future<void> _ack(
    BuildContext context,
    WidgetRef ref,
    KitchenAlert alert,
  ) async {
    if (alert.acknowledged) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(alertsProvider.notifier).acknowledge(alert);
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not acknowledge: $error')),
      );
    }
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert, required this.onAck});
  final KitchenAlert alert;
  final VoidCallback onAck;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(alert.severity);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: CalmSurface(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: alert.acknowledged ? null : onAck,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: color, width: 4)),
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SoftIcon(_icon(alert.component), color: color, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alert.message,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${alert.component.toUpperCase()}  |  ${_time(alert.ts)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (!alert.acknowledged)
                  const Icon(
                    Icons.check_circle_outline,
                    size: 22,
                    color: mutedInk,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _icon(String component) => switch (component) {
    'lpg' => Icons.local_fire_department_outlined,
    'pantry' => Icons.inventory_2_outlined,
    'pest' => Icons.radar,
    'child' => Icons.child_care,
    _ => Icons.warning_amber,
  };
  String _time(DateTime value) =>
      '${value.toLocal().month}/${value.toLocal().day} ${value.toLocal().hour.toString().padLeft(2, '0')}:${value.toLocal().minute.toString().padLeft(2, '0')}';
}
