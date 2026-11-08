import 'package:flutter/material.dart';

/// loading / content / error / empty 三态切换的统一过渡容器。
///
/// 此前三态是硬切（页面闪变）；这里包一层 AnimatedSwitcher 做一次
/// 250ms fade。**子 widget 必须带稳定且互不相同的 [Key]**——
/// AnimatedSwitcher 靠 key 判断是否需要过渡（调用方用
/// `ValueKey('loading')` / `ValueKey('content')` 之类）。
class StateTransitionSwitch extends StatelessWidget {
  final Widget child;

  final Duration duration;

  const StateTransitionSwitch({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 250),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: child,
    );
  }
}
