/// Small building blocks for the Engine Lab screens.
///
/// Kept together so the dashboard, the benchmark tab and the report share one
/// visual language — and so the rating bar (point estimate plus its interval)
/// is drawn in one place, because a rating shown without its uncertainty is the
/// thing this whole feature exists to stop.
library;

import 'package:flutter/material.dart';

import '../../bench/elo.dart';

/// A titled card section.
class LabSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;

  const LabSection({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.actions = const [],
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                ),
                ...actions,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// A label/value line that never wraps awkwardly.
class LabInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasise;

  const LabInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasise = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: emphasise
                  ? theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)
                  : theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// Colour for a rating quality grade.
Color qualityColor(BuildContext context, RatingQuality quality) {
  final scheme = Theme.of(context).colorScheme;
  switch (quality) {
    case RatingQuality.high:
      return scheme.primary;
    case RatingQuality.moderate:
      return scheme.tertiary;
    case RatingQuality.low:
      return scheme.secondary;
    case RatingQuality.insufficient:
      return scheme.error;
  }
}

/// A compact grade badge ("moderate", "insufficient", …).
class QualityBadge extends StatelessWidget {
  final RatingQuality quality;
  final String label;

  const QualityBadge({super.key, required this.quality, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = qualityColor(context, quality);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// A rating with its 95% interval drawn as a bar.
///
/// The whiskers are the point: two engines whose bars overlap are not ranked by
/// this run, whatever order the table shows them in.
class RatingBar extends StatelessWidget {
  final double rating;
  final double ciLow;
  final double ciHigh;
  final double minRating;
  final double maxRating;
  final String label;
  final Color color;

  const RatingBar({
    super.key,
    required this.rating,
    required this.ciLow,
    required this.ciHigh,
    required this.label,
    this.minRating = 0,
    this.maxRating = 0,
    this.color = Colors.blue,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasRange = minRating.isFinite && maxRating.isFinite && maxRating > minRating;
    final low = hasRange ? minRating : rating - 200;
    final high = hasRange ? maxRating : rating + 200;
    double position(double value) {
      final span = (high - low).abs() < 1 ? 1.0 : (high - low);
      if (value == double.negativeInfinity) return 0;
      if (value == double.infinity) return 1;
      if (!value.isFinite) return 0.5;
      return ((value - low) / span).clamp(0.0, 1.0).toDouble();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis),
            ),
            Text(
              '${rating.toStringAsFixed(0)}',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 4),
            Text(
              '±${((ciHigh - ciLow) / 2).toStringAsFixed(0)}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 10,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final start = position(ciLow) * width;
              final end = position(ciHigh) * width;
              final center = position(rating) * width;
              return Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 4,
                    child: Container(
                      height: 2,
                      color: theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  Positioned(
                    left: start,
                    top: 3,
                    child: Container(
                      width: (end - start).clamp(2.0, width).toDouble(),
                      height: 4,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Positioned(
                    left: (center - 3).clamp(0.0, width > 6 ? width - 6 : 0.0).toDouble(),
                    top: 0,
                    child: Container(
                      width: 6,
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// A label with a coloured state chip.
class StateChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const StateChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Shown instead of a table when there is nothing to show yet.
class LabEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const LabEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        children: [
          Icon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (action != null) ...[
            const SizedBox(height: 16),
            action!,
          ],
        ],
      ),
    );
  }
}

/// A horizontal progression bar, used for rating history.
///
/// Deliberately a plain widget rather than a chart package: it has to render
/// the same on a phone and on a 4K monitor, and a bar per run says what a
/// sparkline would while staying readable.
class ProgressionBar extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final Color color;
  final String emptyLabel;

  const ProgressionBar({
    super.key,
    required this.values,
    required this.labels,
    required this.color,
    this.emptyLabel = 'No history',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (values.isEmpty) {
      return Text(emptyLabel,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant));
    }
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final span = (max - min).abs() < 1 ? 1.0 : max - min;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < values.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              children: [
                SizedBox(
                  width: 92,
                  child: Text(
                    labels.length > i ? labels[i] : '',
                    style: theme.textTheme.labelSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: ((values[i] - min) / span * 0.85 + 0.15)
                        .clamp(0.02, 1.0)
                        .toDouble(),
                    child: Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 44,
                  child: Text(
                    values[i].toStringAsFixed(0),
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
