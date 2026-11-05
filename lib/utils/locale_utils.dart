import 'package:flutter/material.dart';

/// Check if current locale is Chinese
bool isZhLocale(BuildContext context) {
  return Localizations.localeOf(context).languageCode == 'zh';
}

/// Get locale key for comparison (e.g., 'en', 'zh', 'zh_Hant', 'ja', 'ko').
/// Traditional Chinese is keyed 'zh_Hant' whether it comes from scriptCode
/// (zh-Hant) or region (zh-TW/HK/MO), so it never collides with 'zh'.
String? getLocaleKey(Locale? locale) {
  if (locale == null) return null;
  if (locale.languageCode == 'zh') {
    if (locale.scriptCode == 'Hant') return 'zh_Hant';
    final country = locale.countryCode;
    if (country == 'TW' || country == 'HK' || country == 'MO') {
      return 'zh_Hant';
    }
    return 'zh';
  }
  if (locale.countryCode != null && locale.countryCode!.isNotEmpty) {
    return '${locale.languageCode}_${locale.countryCode}';
  }
  return locale.languageCode;
}

/// Parse locale key to Locale object
Locale? parseLocaleKey(String? key) {
  if (key == null) return null;
  if (key == 'zh_Hant' || key == 'zh_TW' || key == 'zh_HK' || key == 'zh_MO') {
    return const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
  }
  final parts = key.split('_');
  if (parts.length == 2) {
    return Locale(parts[0], parts[1]);
  }
  return Locale(parts[0]);
}

/// Get localized text with fallback
String getLocalizedText(BuildContext context, String zhText, String enText) {
  return isZhLocale(context) ? zhText : enText;
}
