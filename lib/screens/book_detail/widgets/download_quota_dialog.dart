import 'dart:async';
import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:flutter/material.dart';
import '../../../l10n/generated/app_localizations.dart';

/// 用户自己 Z 站账号当日下载次数用尽时的提醒弹窗。
void showDownloadQuotaDialog(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  unawaited(AwesomeDialog(
    context: context,
    dialogType: DialogType.warning,
    animType: AnimType.bottomSlide,
    title: l10n.downloadQuotaTitle,
    desc: l10n.downloadQuotaDesc,
    btnOkColor: Theme.of(context).colorScheme.primary,
    btnOkOnPress: () {},
  ).show());
}
