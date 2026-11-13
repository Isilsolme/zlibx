import 'dart:async';

import 'package:flutter/material.dart';

/// Shared Material 3 confirmation/info dialog.
///
/// Replaces AwesomeDialog (which pulled the 7 MB Rive native library just for
/// its slide animation). The dialog itself uses the app's 28dp dialog theme;
/// buttons are filled/tonal M3 actions.
Future<void> showAppDialog(
  BuildContext context, {
  required String title,
  String? message,
  String? cancelLabel,
  FutureOr<void> Function()? onCancel,
  String? confirmLabel,
  FutureOr<void> Function()? onConfirm,
  Color? confirmColor,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: message == null ? null : Text(message),
        actions: <Widget>[
          if (cancelLabel != null)
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                final callback = onCancel;
                if (callback != null) unawaited(Future<void>.sync(callback));
              },
              child: Text(cancelLabel),
            ),
          if (confirmLabel != null)
            FilledButton(
              style: confirmColor == null
                  ? null
                  : FilledButton.styleFrom(backgroundColor: confirmColor),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                final callback = onConfirm;
                if (callback != null) unawaited(Future<void>.sync(callback));
              },
              child: Text(confirmLabel),
            ),
        ],
      );
    },
  );
}
