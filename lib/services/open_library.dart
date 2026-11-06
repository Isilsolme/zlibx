// Ported from warreth/OpenlibExtended (AGPL-3.0) — Open Library
// trending discovery feed.
// Original file: lib/services/open_library.dart (OpenLibrary only;
// GoodReads / PenguinRandomHouse / BookDigits were not ported — zlibx
// only needs the Open Library feed).
// zlibx is AGPL-3.0 (see LICENSE); upstream MIT attribution for
// shiyi-0x7f/olib-mobile is preserved in LICENSE.
//
// The feed is the public https://openlibrary.org/trending/daily page
// (no login, no key); failures return an empty list and the caller
// hides the section.

// Package imports:
import 'package:dio/dio.dart';
import 'package:html/parser.dart' show parse;

// Project imports:
import 'package:zlibx/services/external_logger.dart';

class TrendingBookData {
  final String? title;
  final String? thumbnail;
  TrendingBookData({this.title, this.thumbnail});
}

abstract class TrendingBooksImpl {
  String url = '';
  int timeOutDuration = 20;
  final AppLogger _logger = AppLogger();
  List<TrendingBookData> _parser(dynamic data);

  Future<List<TrendingBookData>> trendingBooks() async {
    try {
      final dio = Dio();
      final response = await dio.get(url,
          options: Options(
              sendTimeout: Duration(seconds: timeOutDuration),
              receiveTimeout: Duration(seconds: timeOutDuration)));
      return _parser(response.data.toString());
    } on DioException catch (e) {
      _logger.warning('Failed to fetch trending books',
          tag: 'TrendingBooks', metadata: {'url': url, 'error': e.message});
      return [];
    }
  }
}

class OpenLibrary extends TrendingBooksImpl {
  OpenLibrary() {
    super.url = "https://openlibrary.org/trending/daily";
  }

  @override
  List<TrendingBookData> _parser(data) {
    var document = parse(data.toString());
    var bookList =
        document.querySelectorAll('li[class="searchResultItem sri--w-main"]');
    List<TrendingBookData> trendingBooks = [];
    for (var element in bookList) {
      if (element.querySelector('h3[class="booktitle"]')?.text != null &&
          element.querySelector('img[itemprop="image" ]')?.attributes['src'] !=
              null) {
        String? thumbnail =
            element.querySelector('img[itemprop="image" ]')?.attributes['src'];
        trendingBooks.add(
          TrendingBookData(
              title:
                  element.querySelector('h3[class="booktitle"]')?.text.trim(),
              thumbnail: 'https:${thumbnail.toString()}'),
        );
      }
    }
    return trendingBooks;
  }

  @override
  Future<List<TrendingBookData>> trendingBooks() async {
    try {
      final dio = Dio();
      const timeOutDuration = 5;
      final response = await dio.get(url,
          options: Options(
              sendTimeout: const Duration(seconds: timeOutDuration),
              receiveTimeout: const Duration(seconds: timeOutDuration)));
      final response2 = await dio.get(
          "https://openlibrary.org/trending/daily?page=2",
          options: Options(
              sendTimeout: const Duration(seconds: timeOutDuration),
              receiveTimeout: const Duration(seconds: timeOutDuration)));
      return _parser('${response.data.toString()}${response2.data.toString()}');
    } on DioException catch (e) {
      _logger.warning('Failed to fetch OpenLibrary trending books',
          tag: 'OpenLibrary', metadata: {'error': e.message});
      return [];
    }
  }
}
