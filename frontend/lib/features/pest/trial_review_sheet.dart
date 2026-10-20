import 'package:flutter/material.dart';

import '../../models/pest.dart';
import '../../shared/widgets/clay.dart';

class TrialReviewSheet extends StatefulWidget {
  const TrialReviewSheet({
    super.key,
    required this.trial,
    required this.onSubmit,
  });
  final DeterrenceTrial trial;
  final Future<void> Function(String verdict) onSubmit;

  @override
  State<TrialReviewSheet> createState() => _TrialReviewSheetState();
}

class _TrialReviewSheetState extends State<TrialReviewSheet> {
  bool _busy = false;

  Future<void> _submit(String verdict) async {
    if (_busy) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await widget.onSubmit(verdict);
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Review saved')));
    } catch (error) {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final trial = widget.trial;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Clay.screenPadding,
          12,
          Clay.screenPadding,
          28,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Clay.mutedWarm.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Review deterrence result', style: Clay.text(21, weight: 900)),
            const SizedBox(height: 6),
            Text(
              '${trial.species ?? 'Unidentified pest'} at ${trial.zone}',
              style: Clay.text(16, weight: 700),
            ),
            const SizedBox(height: 2),
            Text(
              'System verdict: ${trial.systemVerdict}',
              style: Clay.text(13.5, weight: 600, color: Clay.mutedWarm),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: _VerdictButton(
                    label: 'Left',
                    icon: Icons.directions_run_rounded,
                    onTap: _busy ? null : () => _submit('left'),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _VerdictButton(
                    label: 'Remains',
                    icon: Icons.location_on_outlined,
                    primary: true,
                    onTap: _busy ? null : () => _submit('remains'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VerdictButton extends StatelessWidget {
  const _VerdictButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final color = primary ? Colors.white : Clay.ink;
    return ClayBox(
      radius: 26,
      depth: 0.8,
      color: Clay.navBar,
      gradient: primary ? clayGradient(Clay.violet) : null,
      onTap: onTap,
      semanticLabel: 'Mark as $label',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(label, style: Clay.text(15.5, weight: 800, color: color)),
          ],
        ),
      ),
    );
  }
}
