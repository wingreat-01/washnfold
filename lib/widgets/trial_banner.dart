import 'package:flutter/material.dart';

/// Thin strip shown at the top of the app while the shop is on its free trial.
class TrialBanner extends StatelessWidget {
  final int daysLeft;
  const TrialBanner({super.key, required this.daysLeft});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final urgent = daysLeft <= 3;
    final bg = urgent ? scheme.errorContainer : scheme.primaryContainer;
    final fg = urgent ? scheme.onErrorContainer : scheme.onPrimaryContainer;
    final text = daysLeft <= 1
        ? 'Free trial: last day'
        : 'Free trial: $daysLeft days left';
    return Material(
      color: bg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.timelapse_rounded, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(
                text,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
