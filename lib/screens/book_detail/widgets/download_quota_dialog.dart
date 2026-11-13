import 'dart:async';
import 'package:flutter/material.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../widgets/app_dialog.dart';

/// 用户自己 Z 站账号当日下载次数用尽时的提醒弹窗。
void showDownloadQuotaDialog(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  unawaited(
    showAppDialog(
      context,
      title: l10n.downloadQuotaTitle,
      message: l10n.downloadQuotaDesc,
      confirmLabel: l10n.confirmOk,
      confirmColor: Theme.of(context).colorScheme.primary,
    ),
  );
}
