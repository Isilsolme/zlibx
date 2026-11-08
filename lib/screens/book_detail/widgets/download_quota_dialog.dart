import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';

import '../../../l10n/s_keys.dart';
/// 用户自己 Z 站账号当日下载次数用尽时的提醒弹窗。
void showDownloadQuotaDialog(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  AwesomeDialog(
    context: context,
    dialogType: DialogType.warning,
    animType: AnimType.bottomSlide,
    title: l10n.get(S.downloadQuotaTitle),
    desc: l10n.get(S.downloadQuotaDesc),
    btnOkColor: Theme.of(context).colorScheme.primary,
    btnOkOnPress: () {},
  ).show();
}
