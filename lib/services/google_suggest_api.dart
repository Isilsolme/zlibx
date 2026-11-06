// Ported from warreth/OpenlibExtended (AGPL-3.0) — search suggestions.
// Original file: lib/services/google_suggest_api.dart
// zlibx is AGPL-3.0 (see LICENSE); upstream MIT attribution for
// shiyi-0x7f/olib-mobile is preserved in LICENSE.
//
// Deviation: upstream returns the placeholder strings 'Suggestion Error'
// / 'Network Error' as suggestions on failure; zlibx returns an empty
// list instead — a failed suggestion fetch must stay silent and never
// show an error as if it were a suggestion.

// Dart imports:
import 'dart:convert';

// Package imports:
import 'package:http/http.dart' as http;

class GoogleSuggestApi {
  // Base URL for the Google Autocomplete service
  static const String _baseUrl =
      'https://suggestqueries.google.com/complete/search';

  /// Fetches a list of search suggestions using the Google Autocomplete
  /// endpoint. Returns an empty list on any failure — the caller shows
  /// nothing rather than an error.
  Future<List<String>> fetchSuggestions(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    // Construct the URL with required parameters
    final url = Uri.parse(_baseUrl).replace(queryParameters: {
      'client': 'firefox', // Client parameter for a clean array response
      'q': cleanQuery,
    });

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        // Google Suggest returns a JSON array. We expect the suggestions
        // to be the second element (index 1).
        final List data = jsonDecode(response.body);

        if (data.length > 1 && data[1] is List) {
          final List rawSuggestions = data[1];

          return rawSuggestions
              .map<String>((item) => item.toString())
              .where((s) => s.isNotEmpty)
              .toList();
        }
        return [];
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }
}
