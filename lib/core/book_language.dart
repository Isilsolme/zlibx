// Ported from warreth/OpenlibExtended (AGPL-3.0) — Anna's Archive / LibGen
// book sources. Original file: lib/core/book_language.dart
// zlibx is AGPL-3.0 (see LICENSE); upstream MIT attribution for
// shiyi-0x7f/olib-mobile is preserved in LICENSE.
/// Canonical language names shared by filters and result metadata.
const bookLanguageNames = <String, String>{
  'en': 'English',
  'es': 'Spanish',
  'fr': 'French',
  'de': 'German',
  'it': 'Italian',
  'pt': 'Portuguese',
  'ru': 'Russian',
  'zh': 'Chinese',
  'ja': 'Japanese',
  'ko': 'Korean',
  'ar': 'Arabic',
  'hi': 'Hindi',
  'ml': 'Malayalam',
  'nl': 'Dutch',
  'pl': 'Polish',
  'tr': 'Turkish',
  'sv': 'Swedish',
  'id': 'Indonesian',
  'vi': 'Vietnamese',
  'cs': 'Czech',
  'el': 'Greek',
  'ro': 'Romanian',
  'hu': 'Hungarian',
  'uk': 'Ukrainian',
  'he': 'Hebrew',
  'th': 'Thai',
  'fa': 'Persian',
  'bn': 'Bengali',
  'fi': 'Finnish',
  'no': 'Norwegian',
  'da': 'Danish',
};

/// Metadata begins with a language name/code, or contains a bracketed code.
String? bookLanguageName(String? info) {
  if (info == null || info.trim().isEmpty) return null;
  final bracket =
      RegExp(r'\[([a-z]{2,3})\]', caseSensitive: false).firstMatch(info);
  if (bracket != null) {
    final name = bookLanguageNames[bracket.group(1)!.toLowerCase()];
    if (name != null) return name;
  }
  final first = info.split(',').first.trim().toLowerCase();
  if (bookLanguageNames.containsKey(first)) return bookLanguageNames[first];
  for (final name in bookLanguageNames.values) {
    if (name.toLowerCase() == first) return name;
  }
  return null;
}
