import 'package:flutter/material.dart';

import 'translations/en.dart' as t_en;
import 'translations/ja.dart' as t_ja;
import 'translations/ko.dart' as t_ko;
import 'translations/zh.dart' as t_zh;
import 'translations/zh_Hant.dart' as t_zh_hant;

/// App translations for all supported languages
class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  static final Map<String, Map<String, String>> _localizedValues = {
    'en': t_en.en,
    'zh': t_zh.zh,
    'zh_Hant': t_zh_hant.zh_Hant,
    'ja': t_ja.ja,
    'ko': t_ko.ko,
  };

  String get(String key) {
    final lookupKey = _lookupKey(locale);
    return _localizedValues[lookupKey]?[key] ??
        _localizedValues['en']?[key] ??
        key;
  }

  // Convenience getters
  String get appName => get('app_name');
  String get cancel => get('cancel');
  String get save => get('save');
  String get close => get('close');
  String get login => get('login');
  String get logout => get('logout');
  String get settings => get('settings');
  String get downloads => get('downloads');
  String get favorites => get('favorites');
  String get search => get('search');
  String get home => get('home');
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['en', 'zh', 'zh_Hant', 'ja', 'ko'].contains(_lookupKey(locale));
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

/// Map a Locale to the translation-map key.
/// Traditional Chinese is distinguished from Simplified by scriptCode
/// (zh-Hant) or by region (TW/HK/MO); everything else uses languageCode.
String _lookupKey(Locale locale) {
  if (locale.languageCode == 'zh') {
    if (locale.scriptCode == 'Hant') return 'zh_Hant';
    final country = locale.countryCode;
    if (country == 'TW' || country == 'HK' || country == 'MO') {
      return 'zh_Hant';
    }
    return 'zh';
  }
  return locale.languageCode;
}

/// Supported locales.
/// NOTE: Locale('zh') (Simplified) must stay first among the zh entries:
/// Flutter's language-only fallback returns the first locale with a matching
/// languageCode, so a zh-CN/zh-SG device resolves to Simplified, while a
/// zh-Hant / zh-TW / zh-HK / zh-MO device matches the Traditional entries
/// above it via script or region.
const supportedLocales = [
  Locale('en'),
  Locale('zh'),
  Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  Locale('zh', 'TW'),
  Locale('zh', 'HK'),
  Locale('zh', 'MO'),
  Locale('ja'),
  Locale('ko'),
];

/// Language display names
const localeDisplayNames = {
  'en': 'English',
  'zh': '简体中文',
  'zh_Hant': '繁體中文',
  'ja': '日本語',
  'ko': '한국어',
};

/// Get locale key for storage
String getLocaleKey(Locale locale) {
  return _lookupKey(locale);
}

/// Parse locale from key
Locale parseLocaleKey(String key) {
  if (key == 'zh_Hant' || key == 'zh_TW' || key == 'zh_HK' || key == 'zh_MO') {
    return const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
  }
  return Locale(key);
}
