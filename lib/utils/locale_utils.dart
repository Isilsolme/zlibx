import 'dart:ui';

/// Display names for the 5 supported locales, keyed by locale key
/// (moved verbatim from the deleted hand-written
/// lib/l10n/app_localizations.dart in gen-l10n step 4).
const localeDisplayNames = {
  'en': 'English',
  'zh': '简体中文',
  'zh_Hant': '繁體中文',
  'ja': '日本語',
  'ko': '한국어',
};

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
