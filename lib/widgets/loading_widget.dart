import 'package:flutter/material.dart';
import 'expressive_loading_indicator.dart';

/// The single loading visual for the whole app: an M3 Expressive morphing
/// blob (see [ExpressiveLoadingIndicator]) with an optional message.
///
/// Three sizes only: page 56, inline / in-button 20, list-bottom 28.
class LoadingWidget extends StatelessWidget {
  final String? message;
  final double size;
  final Color? color;
  final double? value;
  final EdgeInsetsGeometry padding;
  final bool _centered;

  const LoadingWidget({
    super.key,
    this.message,
    this.size = 56,
    this.color,
    this.value,
    this.padding = EdgeInsets.zero,
  }) : _centered = true;

  /// Full-page loading: centered 56 blob + optional message.
  const LoadingWidget.page({
    super.key,
    this.message,
    this.padding = EdgeInsets.zero,
  }) : size = 56,
       color = null,
       value = null,
       _centered = true;

  /// Inline / in-button loading: a bare 20 blob, no message, no centering.
  const LoadingWidget.inline({
    super.key,
    this.size = 20,
    this.color,
    this.value,
  }) : message = null,
       padding = EdgeInsets.zero,
       _centered = false;

  /// "Load more" footer: Padding(16) + centered 28 blob.
  const LoadingWidget.more({super.key})
    : message = null,
      size = 28,
      color = null,
      value = null,
      padding = const EdgeInsets.all(16),
      _centered = true;

  @override
  Widget build(BuildContext context) {
    final indicator = ExpressiveLoadingIndicator(
      size: size,
      color: color,
      value: value,
    );
    if (!_centered) {
      return SizedBox.square(dimension: size, child: indicator);
    }
    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        indicator,
        if (message != null) ...[
          const SizedBox(height: 24),
          Text(
            message!,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
    content = Center(child: content);
    if (padding != EdgeInsets.zero) {
      content = Padding(padding: padding, child: content);
    }
    return content;
  }
}
