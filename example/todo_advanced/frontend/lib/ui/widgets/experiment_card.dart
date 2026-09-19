import 'package:flutter/material.dart';

/// One experiment in the Sync lab.
///
/// Every card says the same four things, in the same order, so the reader
/// learns to look for them: what it is, what to do, what should happen, and
/// — the part that matters most in a sync demo — what must *not* happen.
class ExperimentCard extends StatelessWidget {
  const ExperimentCard({
    super.key,
    required this.number,
    required this.title,
    required this.doThis,
    required this.youShouldSee,
    required this.mustNotHappen,
    required this.control,
    this.armed = false,
  });

  final int number;
  final String title;
  final String doThis;
  final String youShouldSee;
  final String mustNotHappen;

  /// The switch or buttons that arm this experiment.
  final Widget control;

  /// Whether the experiment is currently armed, for the highlight.
  final bool armed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: armed ? theme.colorScheme.tertiaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    '$number',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                if (armed)
                  Chip(
                    label: const Text('ARMED'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: theme.colorScheme.tertiary,
                    labelStyle: TextStyle(
                      color: theme.colorScheme.onTertiary,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _Line(label: 'Do this', text: doThis, icon: Icons.touch_app),
            _Line(
              label: 'You should see',
              text: youShouldSee,
              icon: Icons.visibility_outlined,
            ),
            _Line(
              label: 'What must not happen',
              text: mustNotHappen,
              icon: Icons.block,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            control,
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.text,
    required this.icon,
    this.color,
  });

  final String label;
  final String text;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 16,
            color: color ?? theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: theme.textTheme.bodySmall,
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: color ?? theme.colorScheme.onSurface,
                    ),
                  ),
                  TextSpan(text: text),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
