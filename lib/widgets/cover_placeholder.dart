import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../theme/app_metrics.dart';

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

/// Animated gradient sweep, 1500 ms per pass ([AppMotion.shimmer], the same
/// timing as the old BookCard shimmer it replaces). Every visible shimmer
/// shares one controller, so all covers sweep in phase.
class _ShimmerCover extends StatefulWidget {
  const _ShimmerCover();

  @override
  State<_ShimmerCover> createState() => _ShimmerCoverState();
}

/// One controller for every shimmer on screen. A grid of 50 loading covers
/// used to create 50 AnimationControllers (50 tickers); the holder is
/// reference-counted by the widgets currently allowed to animate (system
/// animations on + TickerMode enabled). The first consumer starts the
/// repeat, the last one stops it, so a backgrounded route does not keep the
/// ticker running.
class _SharedShimmer {
  _SharedShimmer._();

  static final _SharedShimmer instance = _SharedShimmer._();

  final TickerProvider _vsync = _ShimmerTickerProvider();

  late final AnimationController _controller = AnimationController(
    vsync: _vsync,
    duration: AppMotion.shimmer,
  );

  late final Animation<double> animation =
      Tween<double>(begin: -1.0, end: 2.0).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
  );

  int _consumers = 0;

  void attach() {
    _consumers++;
    if (!_controller.isAnimating) _controller.repeat();
  }

  void detach() {
    if (_consumers > 0) _consumers--;
    if (_consumers == 0) _controller.stop();
  }
}

/// A bare [Ticker]: TickerMode muting is handled by [_SharedShimmer]'s
/// per-consumer reference count, not by a single widget's mixin.
class _ShimmerTickerProvider implements TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

class _ShimmerCoverState extends State<_ShimmerCover> {
  bool _attached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shouldAnimate = !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (shouldAnimate == _attached) return;
    _attached = shouldAnimate;
    if (shouldAnimate) {
      _SharedShimmer.instance.attach();
    } else {
      _SharedShimmer.instance.detach();
    }
  }

  @override
  void dispose() {
    if (_attached) {
      _attached = false;
      _SharedShimmer.instance.detach();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor =
        isDark ? const Color(0xFF2A2A2A) : const Color(0xFFEEEEEE);
    final highlightColor =
        isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF5F5F5);
    final animation = _SharedShimmer.instance.animation;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final value = animation.value;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [baseColor, highlightColor, baseColor],
              stops: [
                (value - 0.3).clamp(0.0, 1.0),
                value.clamp(0.0, 1.0),
                (value + 0.3).clamp(0.0, 1.0),
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
