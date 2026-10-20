import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ws_client.dart';
import '../../features/alerts/alerts_providers.dart';
import 'clay.dart';

/// Scrolling page shell shared by the clay tabs: ivory background, content
/// centred at max 430px, pull-to-refresh, and bottom space for the floating
/// nav pill.
class ClayPage extends StatelessWidget {
  const ClayPage({super.key, required this.onRefresh, required this.children});

  final Future<void> Function() onRefresh;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Clay.background,
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Clay.maxContentWidth),
        child: RefreshIndicator(
          color: Clay.violet.last,
          backgroundColor: Clay.navBar,
          onRefresh: onRefresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverSafeArea(
                bottom: false,
                sliver: SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    Clay.screenPadding,
                    14,
                    Clay.screenPadding,
                    // Clear the floating nav pill that overlays the page.
                    MediaQuery.paddingOf(context).bottom + 24,
                  ),
                  sliver: SliverList.list(children: children),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Small label, big title, and the alert bell with its live unread count.
class ClayScreenHeader extends ConsumerWidget {
  const ClayScreenHeader({super.key, required this.label, required this.title});

  final String label, title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadAlertsProvider);
    final connection = ref.watch(liveConnectionProvider).value;
    final reconnecting =
        connection == LiveConnectionState.reconnecting ||
        connection == LiveConnectionState.connecting;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Clay.text(14, weight: 700, color: Clay.mutedGreen),
              ),
              Text(title, style: Clay.text(27, weight: 900, height: 1.2)),
              if (reconnecting)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Reconnecting...',
                    style: Clay.text(12, weight: 700, color: Clay.warnPillText),
                  ),
                ),
            ],
          ),
        ),
        _BellButton(unread: unread),
      ],
    );
  }
}

class _BellButton extends StatelessWidget {
  const _BellButton({required this.unread});
  final int unread;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 56,
    height: 56,
    child: Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 50,
          height: 50,
          child: ClayBox(
            radius: 20,
            depth: 0.6,
            color: Clay.navBar,
            semanticLabel:
                unread > 0 ? 'Alerts, $unread unread' : 'Alerts, none unread',
            onTap: () => context.push('/alerts'),
            child: const Center(
              child: Icon(
                Icons.notifications_none_rounded,
                color: Clay.ink,
                size: 24,
              ),
            ),
          ),
        ),
        if (unread > 0)
          Positioned(
            top: 0,
            right: 0,
            child: ExcludeSemantics(
              child: Container(
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Clay.badge,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Clay.badge.withValues(alpha: 0.4),
                      offset: const Offset(0, 3),
                      blurRadius: 7,
                    ),
                  ],
                ),
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  style: Clay.text(12, weight: 900, color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class ClaySectionTitle extends StatelessWidget {
  const ClaySectionTitle(this.title, {super.key, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title, style: Clay.text(19, weight: 900)),
              ),
            ),
            if (trailing != null)
              Text(
                trailing!,
                style: Clay.text(12.5, weight: 700, color: Clay.mutedGreen),
              ),
          ],
        ),
        if (subtitle != null)
          Text(
            subtitle!,
            style: Clay.text(13.5, weight: 600, color: Clay.mutedWarm),
          ),
      ],
    ),
  );
}

/// Fades and slides a block in once when it first appears, staggered by
/// [index]. Skipped when the user asked for reduced motion.
class ClayEntrance extends StatefulWidget {
  const ClayEntrance({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<ClayEntrance> createState() => _ClayEntranceState();
}

class _ClayEntranceState extends State<ClayEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
      return;
    }
    Future<void>.delayed(
      Duration(milliseconds: 70 * widget.index.clamp(0, 8)),
      () {
        if (mounted) _controller.forward();
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _curve,
    child: SlideTransition(
      position: Tween(
        begin: const Offset(0, 0.08),
        end: Offset.zero,
      ).animate(_curve),
      child: widget.child,
    ),
  );
}

/// Repeats [builder] on a controller unless the user asked for reduced motion.
abstract class ClayLoopState<T extends StatefulWidget> extends State<T>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  Duration get period;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(vsync: this, duration: period);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.stop();
    } else if (!controller.isAnimating) {
      controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

class ClayPulsingDot extends StatefulWidget {
  const ClayPulsingDot({super.key});
  @override
  State<ClayPulsingDot> createState() => _ClayPulsingDotState();
}

class _ClayPulsingDotState extends ClayLoopState<ClayPulsingDot> {
  @override
  Duration get period => const Duration(milliseconds: 1100);

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: AnimatedBuilder(
    animation: controller,
    builder: (_, _) {
      final t = Curves.easeInOut.transform(controller.value);
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.55 + 0.45 * t),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.5 * (1 - t)),
              blurRadius: 2 + 6 * t,
              spreadRadius: 4 * t,
            ),
          ],
        ),
      );
    },
    ),
  );
}

class ClayFloating extends StatefulWidget {
  const ClayFloating({super.key, required this.child});
  final Widget child;
  @override
  State<ClayFloating> createState() => _ClayFloatingState();
}

class _ClayFloatingState extends ClayLoopState<ClayFloating> {
  @override
  Duration get period => const Duration(milliseconds: 3000);

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    // The blob is painted once into its own layer; only the offset animates.
    child: RepaintBoundary(child: widget.child),
    builder:
        (_, child) => Transform.translate(
          offset: Offset(0, -5 + 10 * Curves.easeInOut.transform(controller.value)),
          child: child,
        ),
  );
}


/// Loading or error placeholder card for clay pages.
class ClayMessageCard extends StatelessWidget {
  const ClayMessageCard({super.key, required this.message, this.onRetry});
  final String message;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) => ClayBox(
    radius: 30,
    color: Clay.cardWarning,
    padding: const EdgeInsets.all(28),
    child: Column(
      children: [
        if (onRetry == null)
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Clay.violet.last,
            ),
          )
        else
          const Icon(Icons.cloud_off_rounded, size: 40, color: Clay.mutedWarm),
        const SizedBox(height: 14),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Clay.text(15, weight: 700, color: Clay.mutedGreen),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Clay.violet.last,
              shape: const StadiumBorder(),
              minimumSize: const Size(120, 48),
            ),
            onPressed: onRetry,
            child: Text(
              'Try again',
              style: Clay.text(15, weight: 800, color: Colors.white),
            ),
          ),
        ],
      ],
    ),
  );
}
