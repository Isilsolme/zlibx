// Excerpt ported from warreth/OpenlibExtended (AGPL-3.0) —
// lib/services/search_manager.dart (SearchProviderId, SearchProvider,
// SearchQuery, AnnasArchiveProvider, SearchManagerResult only).
// ZlibraryProvider, WelibProvider and SearchManager were NOT taken.
// olib lite is AGPL-3.0 (see LICENSE).
// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:olib_mobile/services/annas_archieve.dart';

/// One searchable catalog the app can query.
enum SearchProviderId { annasArchive, libgen, zlibrary, welib }

/// A source of [BookData] results. Implementations own their fetching,
/// parsing and error handling - the manager merges whatever comes back.
abstract class SearchProvider {
  /// Stable id for persistence and settings toggles.
  SearchProviderId get id;

  /// Human name shown in settings.
  String get displayName;

  /// Runs a search. Must return [] when nothing matches; throws when the
  /// provider is unreachable. A throw is contained by the manager.
  Future<List<BookData>> search(SearchQuery query);
}

/// The filters the results page collects, in provider-neutral form.
///
/// [author], [publisher] and [year] carry field-specific values from
/// the advanced search panel; providers translate them into whatever
/// their backend supports.
@immutable
class SearchQuery {
  final String text;
  final String content;
  final String sort;
  final String fileType;
  final String language;
  final String year;
  final String author;
  final String publisher;
  final bool filtersEnabled;
  final int page;

  /// Null keeps the automatic fallback chain; a selection searches only that catalog.
  final SearchProviderId? source;

  const SearchQuery({
    required this.text,
    this.content = '',
    this.sort = '',
    this.fileType = '',
    this.language = '',
    this.year = '',
    this.author = '',
    this.publisher = '',
    this.filtersEnabled = false,
    this.page = 1,
    this.source,
  });

  bool get isEmpty =>
      text.trim().isEmpty && author.trim().isEmpty && publisher.trim().isEmpty;
}

/// Anna's Archive behind the provider interface: the existing
/// AnnasArchieve service with its challenge handling, unchanged.
class AnnasArchiveProvider implements SearchProvider {
  AnnasArchiveProvider({AnnasArchieve? api}) : _api = api ?? AnnasArchieve();

  final AnnasArchieve _api;

  @override
  SearchProviderId get id => SearchProviderId.annasArchive;

  @override
  String get displayName => "Anna's Archive";

  @override
  Future<List<BookData>> search(SearchQuery query) {
    return _api.searchBooks(
      searchQuery: query.text,
      content: query.content,
      sort: query.sort,
      fileType: query.fileType,
      language: query.language,
      year: query.year,
      author: query.author,
      publisher: query.publisher,
      enableFilters: query.filtersEnabled,
      page: query.page,
    );
  }
}

/// Combined outcome of a fan-out search.
@immutable
class SearchManagerResult {
  final List<BookData> books;

  /// Display names of providers that threw; the UI can mention them while
  /// still showing the surviving results.
  final List<String> failedProviders;

  /// The catalog the returned books came from ('' when several sources
  /// contributed or none found anything). Single value because the chain
  /// stops at the first provider with results.
  final String resultSource;

  const SearchManagerResult(
      {required this.books,
      required this.failedProviders,
      this.resultSource = ''});
}
