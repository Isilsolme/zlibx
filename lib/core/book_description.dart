// Ported from warreth/OpenlibExtended (AGPL-3.0) — description
// normalisation for book detail pages.
// Original file: lib/core/book_description.dart
// zlibx is AGPL-3.0 (see LICENSE); upstream MIT attribution for
// shiyi-0x7f/olib-mobile is preserved in LICENSE.

/// Missing metadata must remain absent rather than becoming the word "null".
String? normalizedBookDescription(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty || text.toLowerCase() == 'null') return null;
  return text;
}
