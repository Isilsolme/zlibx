import 'package:flutter/material.dart';

/// 全 app 统一的轻提示入口。此前 18 个文件各自手写
/// `ScaffoldMessenger.of(context).showSnackBar(...)`，样式、时长、
/// 浮起行为各自为政；收口到这里，改一处全局生效。
///
/// 普通文本提示走 [showAppSnack]（统一 floating + 2.5s）；错误
/// 提示传 `error: true`（errorContainer 底色，与普通提示区分）；
/// 需要完全自定义内容（图标行、内嵌按钮，如 home 的更新提示）时
/// 走 [showAppSnackRaw]，只统一 messenger 获取方式。
void showAppSnack(
  BuildContext context,
  String message, {
  SnackBarAction? action,
  Duration? duration,
  bool error = false,
}) {
  Color? background;
  TextStyle? contentStyle;
  if (error) {
    final cs = Theme.of(context).colorScheme;
    background = cs.errorContainer;
    contentStyle = TextStyle(color: cs.onErrorContainer);
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, style: contentStyle),
      backgroundColor: background,
      behavior: SnackBarBehavior.floating,
      action: action,
      duration: duration ?? const Duration(milliseconds: 2500),
    ),
  );
}

/// 完全自定义 SnackBar 内容时的入口。
void showAppSnackRaw(BuildContext context, SnackBar snackBar) {
  ScaffoldMessenger.of(context).showSnackBar(snackBar);
}

/// 已持有 [ScaffoldMessengerState] 时的小工具（异步回调里提前
/// 取好 messenger、避免再用 context 的场景）。需要 error 色背景
/// 时走 [showAppSnack]（那边拿得到 ColorScheme）。
void showAppSnackOn(
  ScaffoldMessengerState messenger,
  String message, {
  Duration? duration,
}) {
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: duration ?? const Duration(milliseconds: 2500),
    ),
  );
}
