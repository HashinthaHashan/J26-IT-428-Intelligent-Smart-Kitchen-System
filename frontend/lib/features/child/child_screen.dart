import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/api_client.dart';
import '../../models/child.dart';
import '../../shared/widgets/loading_error_view.dart';
import '../../shared/widgets/risk_badge.dart';
import '../../shared/widgets/calm_surface.dart';
import 'child_providers.dart';

class ChildScreen extends ConsumerWidget {
  const ChildScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(childProvider);
    return value.when(
      loading: () => const LoadingErrorView.loading(),
      error:
          (error, _) => LoadingErrorView.error(
            message: userFacingError(error),
            onRetry: () => ref.read(childProvider.notifier).refresh(),
          ),
      data: (data) {
        final event = data.snapshot.event;
        final empty =
            event.persons.isEmpty &&
            event.hazards.isEmpty &&
            event.poses.isEmpty;
        return RefreshIndicator(
          onRefresh: ref.read(childProvider.notifier).refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
            children: [
              CalmSurface(
                color: statusColor(
                  data.snapshot.prediction.riskLevel,
                ).withValues(alpha: 0.08),
                child: Row(
                  children: [
                    SoftIcon(
                      data.snapshot.prediction.riskLevel == 'Safe'
                          ? Icons.verified_user_outlined
                          : Icons.warning_amber_outlined,
                      color: statusColor(data.snapshot.prediction.riskLevel),
                      size: 54,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Current safety status',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 4),
                          RiskBadge(
                            status: data.snapshot.prediction.riskLevel,
                            large: true,
                          ),
                          if (data.snapshot.prediction.riskLevel != 'Safe' &&
                              data.why != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              data.why!,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const SectionHeading(
                title: 'Current scene',
                subtitle: 'Live positions and detected hazards',
              ),
              const SizedBox(height: 12),
              CalmSurface(
                padding: const EdgeInsets.all(8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: AspectRatio(
                    aspectRatio: event.w / event.h,
                    child:
                        empty
                            ? const DecoratedBox(
                              decoration: BoxDecoration(color: softSurface),
                              child: LoadingErrorView.empty(
                                emptyTitle: 'No people or hazards detected',
                                emptyIcon: Icons.person_search_outlined,
                              ),
                            )
                            : CustomPaint(
                              painter: PosePainter(event),
                              child: const SizedBox.expand(),
                            ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  const _Legend(color: safeGreen, label: 'Child'),
                  const _Legend(color: Color(0xFF3478C5), label: 'Adult'),
                  _Legend(color: statusColor('Danger'), label: 'Hazard'),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class PosePainter extends CustomPainter {
  const PosePainter(this.event);
  final ChildEvent event;
  static const edges = [
    (5, 7),
    (7, 9),
    (6, 8),
    (8, 10),
    (5, 6),
    (5, 11),
    (6, 12),
    (11, 12),
    (11, 13),
    (13, 15),
    (12, 14),
    (14, 16),
    (0, 5),
    (0, 6),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = softSurface);
    for (final person in event.persons) {
      _box(
        canvas,
        size,
        person,
        person.cls == 'child' ? safeGreen : const Color(0xFF3478C5),
      );
    }
    for (final hazard in event.hazards) {
      _box(
        canvas,
        size,
        hazard,
        statusColor('Danger'),
        label: hazard.cls.replaceAll('_', ' '),
      );
    }
    final line =
        Paint()
          ..color = accent
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round;
    final joint = Paint()..color = accent;
    for (final pose in event.poses) {
      for (final edge in edges) {
        if (pose.length <= edge.$1 || pose.length <= edge.$2) {
          continue;
        }
        final a = pose[edge.$1], b = pose[edge.$2];
        if (a.length < 3 || b.length < 3 || a[2] < 0.25 || b[2] < 0.25) {
          continue;
        }
        canvas.drawLine(
          Offset(a[0] * size.width, a[1] * size.height),
          Offset(b[0] * size.width, b[1] * size.height),
          line,
        );
      }
      for (final point in pose) {
        if (point.length >= 3 && point[2] >= 0.25) {
          canvas.drawCircle(
            Offset(point[0] * size.width, point[1] * size.height),
            3.5,
            joint,
          );
        }
      }
    }
  }

  void _box(
    Canvas canvas,
    Size size,
    BoxDetection detection,
    Color color, {
    String? label,
  }) {
    if (detection.box.length != 4) return;
    final rect = Rect.fromLTRB(
      detection.box[0] * size.width,
      detection.box[1] * size.height,
      detection.box[2] * size.width,
      detection.box[3] * size.height,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    if (label != null) {
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      painter.paint(
        canvas,
        Offset(
          rect.left,
          (rect.top - painter.height - 2).clamp(0, size.height).toDouble(),
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant PosePainter oldDelegate) =>
      oldDelegate.event != event;
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(label),
    ],
  );
}
