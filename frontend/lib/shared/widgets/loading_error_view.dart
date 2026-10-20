import 'package:flutter/material.dart';

import '../../core/theme.dart';

class LoadingErrorView extends StatelessWidget {
  const LoadingErrorView.loading({super.key})
    : message = null,
      onRetry = null,
      emptyTitle = null,
      emptyIcon = null;

  const LoadingErrorView.error({
    super.key,
    required this.message,
    required this.onRetry,
  }) : emptyTitle = null,
       emptyIcon = null;

  const LoadingErrorView.empty({
    super.key,
    required this.emptyTitle,
    this.emptyIcon = Icons.inbox_outlined,
  }) : message = null,
       onRetry = null;

  final String? message;
  final VoidCallback? onRetry;
  final String? emptyTitle;
  final IconData? emptyIcon;

  @override
  Widget build(BuildContext context) {
    if (emptyTitle != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: softSurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(emptyIcon, size: 28, color: mutedInk),
              ),
              const SizedBox(height: 12),
              Text(
                emptyTitle!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
        ),
      );
    }
    if (message == null) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 42, color: mutedInk),
            const SizedBox(height: 12),
            Text(message!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
