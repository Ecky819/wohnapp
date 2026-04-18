import 'package:flutter/material.dart';

// ─── Skeleton loader ──────────────────────────────────────────────────────────

/// A single shimmering placeholder card that mimics a ticket list item.
class TicketSkeletonCard extends StatefulWidget {
  const TicketSkeletonCard({super.key});

  @override
  State<TicketSkeletonCard> createState() => _TicketSkeletonCardState();
}

class _TicketSkeletonCardState extends State<TicketSkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    final highlight = Theme.of(context).colorScheme.surfaceContainerHigh;

    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final color = Color.lerp(base, highlight, _anim.value)!;
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // thumbnail placeholder
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Container(width: 48, height: 48, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                          height: 13,
                          width: double.infinity,
                          decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(4))),
                      const SizedBox(height: 6),
                      Container(
                          height: 10,
                          width: 160,
                          decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(4))),
                      const SizedBox(height: 6),
                      Container(
                          height: 18,
                          width: 72,
                          decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(9))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Shows [count] skeleton cards while data is loading.
class TicketSkeletonList extends StatelessWidget {
  const TicketSkeletonList({super.key, this.count = 6});
  final int count;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      itemBuilder: (_, __) => const TicketSkeletonCard(),
    );
  }
}

/// A status badge that adapts its background to the current theme brightness.
///
/// Uses [Color.alphaBlend] with [ColorScheme.surface] so the tinted background
/// always looks correct in both light and dark mode.
class AppStatusBadge extends StatelessWidget {
  const AppStatusBadge({
    super.key,
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final bg = Color.alphaBlend(color.withValues(alpha: 0.18), surface);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Displayed when a list or screen has no data to show.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style:
                    TextStyle(fontSize: 13, color: Colors.grey.shade500),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Displayed when an async operation fails.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 16),
            const Text(
              'Etwas ist schiefgelaufen',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(
                  fontSize: 13, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Erneut versuchen'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
