import 'package:flutter/material.dart';

/// 首屏条目的一次性进场动画（fade + 轻微上滑），不引入动画库。
///
/// [TweenAnimationBuilder] 在条目首次构建时自播一次；[index] 越大
/// 起始越晚（每档 30ms，最多 [maxIndex] 档）形成轻微 stagger；
/// 超过 [maxIndex]（视口外懒加载的新项）直接返回 child 不动画，
/// 避免滚动过程中反复触发。系统关闭动画时（无障碍设置）同样跳过。
class EntranceSlideFade extends StatelessWidget {
  final int index;

  final Widget child;

  /// 参与进场动画的最大档位。
  final int maxIndex;

  const EntranceSlideFade({
    super.key,
    required this.index,
    required this.child,
    this.maxIndex = 8,
  });

  @override
  Widget build(BuildContext context) {
    if (index >= maxIndex || MediaQuery.of(context).disableAnimations) {
      return child;
    }
    final staggerMs = index * 30.0;
    final totalMs = 260.0 + staggerMs;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: totalMs.round()),
      // 总时长含延迟，curve 用 Interval 把真正的动画压到后段，
      // 前段保持透明——等效"延迟后播放"。
      curve: Interval(staggerMs / totalMs, 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 10),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
