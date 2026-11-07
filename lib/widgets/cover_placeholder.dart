import 'package:flutter/material.dart';

/// Shared cover placeholder for every "cover is loading / missing" surface.
///
/// Two variants, one visual language:
/// - [CoverPlaceholder.shimmer]: animated gradient sweep while a cover
///   image is loading (grid cards, detail 3D cover).
/// - [CoverPlaceholder.static]: primary-tinted gradient + book icon when
///   there is no cover or loading failed (list tiles, shelf items, share
///   snapshots, search thumbnails).
class CoverPlaceholder extends StatelessWidget {
  const CoverPlaceholder.shimmer({super.key}) : _shimmer = true;
  const CoverPlaceholder.static({super.key}) : _shimmer = false;

  final bool _shimmer;

  @override
  Widget build(BuildContext context) =>
      _shimmer ? const _ShimmerCover() : const _StaticCover();
}

/// Animated gradient sweep, 1500 ms per pass (same timing as the old
/// BookCard shimmer it replaces). Stops when animations are disabled.
class _ShimmerCover extends StatefulWidget {
  const _ShimmerCover();

  @override
  State<_ShimmerCover> createState() => _ShimmerCoverState();
}

class _ShimmerCoverState extends State<_ShimmerCover>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor =
        isDark ? const Color(0xFF2A2A2A) : const Color(0xFFEEEEEE);
    final highlightColor =
        isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF5F5F5);
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [baseColor, highlightColor, baseColor],
              stops: [
                (_animation.value - 0.3).clamp(0.0, 1.0),
                _animation.value.clamp(0.0, 1.0),
                (_animation.value + 0.3).clamp(0.0, 1.0),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Primary-tinted gradient + book icon (the old BookCard placeholder).
/// The icon scales down on small covers (list tiles, share snapshots).
class _StaticCover extends StatelessWidget {
  const _StaticCover();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  cs.primary.withValues(alpha: 0.15),
                  cs.primary.withValues(alpha: 0.08),
                ]
              : [
                  cs.primary.withValues(alpha: 0.08),
                  cs.primary.withValues(alpha: 0.04),
                ],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final iconSize = (constraints.biggest.shortestSide * 0.5)
              .clamp(16.0, 36.0);
          return Center(
            child: Icon(
              Icons.auto_stories_rounded,
              color: cs.primary.withValues(alpha: isDark ? 0.4 : 0.25),
              size: iconSize,
            ),
          );
        },
      ),
    );
  }
}
