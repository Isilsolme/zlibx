import 'package:flutter/material.dart';

/// 封面图的内存解码宽度：按显示逻辑尺寸 × 设备像素比取整。
///
/// Z-Library 封面原图普遍 500 KB ~ 1.5 MB，不设上限时解码后位图
/// 可达数 MB——长列表快速滑动时 GC 压力直接变成掉帧。此前 8 处
/// 调用点各自手写这个换算，统一到这里（见各调用点 `memCacheWidth`）。
int coverCacheWidth(double logicalWidth, BuildContext context) =>
    (logicalWidth * MediaQuery.devicePixelRatioOf(context)).ceil();
