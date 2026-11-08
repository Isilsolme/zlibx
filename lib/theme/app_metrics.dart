import 'package:flutter/material.dart';

/// 全 app 圆角基线。此前 93 处 `BorderRadius.circular` 散落 14 种
/// 取值（8/12/30/16 占 58 处）；新代码必须用这里，触碰到的旧代码
/// 顺手替换——不做一次性全库替换，控制 diff 噪音。
abstract final class AppRadius {
  /// 卡片/大容器（12）。
  static const BorderRadius card = BorderRadius.all(Radius.circular(12));

  /// 小缩略图/内嵌元素（8）。
  static const BorderRadius thumb = BorderRadius.all(Radius.circular(8));

  /// 大横幅/弹窗（16）。
  static const BorderRadius sheet = BorderRadius.all(Radius.circular(16));

  static BorderRadius circular(double value) => BorderRadius.circular(value);
}

/// 全 app 间距基线。此前 100+ 处 `SizedBox(height/width:)` 散落
/// 8 种取值；收敛策略同 [AppRadius]。
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}
