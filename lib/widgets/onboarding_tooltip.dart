import 'package:flutter/material.dart';

import '../services/onboarding_service.dart';

/// Wraps [child] and shows a one-time tooltip hint the first time the screen
/// is rendered. Hint is stored in SharedPreferences and never shown again.
///
/// The bubble appears above the target widget, pointing down with a small
/// arrow. Tapping anywhere dismisses it.
class OnboardingTooltip extends StatefulWidget {
  const OnboardingTooltip({
    super.key,
    required this.hintKey,
    required this.message,
    required this.child,
  });

  final String hintKey;
  final String message;
  final Widget child;

  @override
  State<OnboardingTooltip> createState() => _OnboardingTooltipState();
}

class _OnboardingTooltipState extends State<OnboardingTooltip> {
  final _anchorKey = GlobalKey();
  OverlayEntry? _entry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
  }

  Future<void> _maybeShow() async {
    if (!mounted) return;
    final seen = await OnboardingService.instance.hasSeen(widget.hintKey);
    if (seen || !mounted) return;
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    _showOverlay();
    await OnboardingService.instance.markSeen(widget.hintKey);
  }

  void _showOverlay() {
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final anchor = box.localToGlobal(Offset.zero);
    final size = box.size;

    _entry = OverlayEntry(
      builder: (_) => _OnboardingOverlay(
        anchorOffset: anchor,
        anchorSize: size,
        message: widget.message,
        onDismiss: _dismiss,
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_entry!);
  }

  void _dismiss() {
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: _anchorKey, child: widget.child);
}

// ─── Overlay widget ────────────────────────────────────────────────────────────

class _OnboardingOverlay extends StatelessWidget {
  const _OnboardingOverlay({
    required this.anchorOffset,
    required this.anchorSize,
    required this.message,
    required this.onDismiss,
  });

  final Offset anchorOffset;
  final Size anchorSize;
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final anchorMidX = anchorOffset.dx + anchorSize.width / 2;
    // Distance from bottom of screen to top of the anchor widget.
    final fromBottom = screenSize.height - anchorOffset.dy;

    // Clamp arrow position to keep it within the bubble.
    final arrowRightOffset =
        (screenSize.width - anchorMidX - 8).clamp(16.0, screenSize.width - 40.0);

    return GestureDetector(
      onTap: onDismiss,
      behavior: HitTestBehavior.translucent,
      child: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.25)),
          ),
          Positioned(
            bottom: fromBottom + 8,
            left: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context).colorScheme.primary,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.lightbulb_outline,
                            color: Colors.white, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            message,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                height: 1.4),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: onDismiss,
                          child: const Icon(Icons.close,
                              color: Colors.white70, size: 18),
                        ),
                      ],
                    ),
                  ),
                ),
                // Downward-pointing arrow aligned with anchor center.
                Padding(
                  padding: EdgeInsets.only(right: arrowRightOffset),
                  child: CustomPaint(
                    size: const Size(16, 8),
                    painter: _TrianglePainter(
                        color: Theme.of(context).colorScheme.primary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  const _TrianglePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width / 2, size.height)
        ..lineTo(size.width, 0)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => old.color != color;
}
