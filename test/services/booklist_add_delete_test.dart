import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

// Booklist add/delete endpoint tests, both confirmed by packet captures
// on 2026-11-09 (Firefox, zh.z-library.sk):
// - Add: `GET /papi/booklist/{booklistId}/add-book/{bookId}`, HTTP 200
//   with `{"success": 1, "book": {"readlist_id": <booklistId>,
//   "book_id": "<bookId>", "date": "..."}}`. No request body (GET).
// - Delete: `GET /papi/booklist/{booklistId}/delete`. The first
//   response is 307 to the same URL with a `__diamwall` set-cookie
//   (the DDoS-Guard challenge); the list was gone from the profile
//   BOOKLISTS tab afterwards. The final response body was never
//   observed, so the implementation counts a final 2xx with an empty
//   body as success (same precedent as createBooklist) and a final
//   JSON body must carry success: 1.
// Removing a book from a list is NOT covered here: its response shape
// was never captured.

const _booklistId = 4090055;
const _bookId = 18337950;
const _addPath = '/papi/booklist/$_booklistId/add-book/$_bookId';
const _deleteListId = 4095945;
const _deletePath = '/papi/booklist/$_deleteListId/delete';

/// Serves canned add/delete responses so the calls run without a
/// network. Records every request's method, path and body.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({
    this.addPayload = const {
      'success': 1,
      'book': {
        'readlist_id': _booklistId,
        'book_id': '$_bookId',
        'date': '2026-11-09T08:04:24.000000Z',
      },
    },
    this.deletePayload = const {'success': 1},
  });

  Map<String, dynamic> addPayload;
  Map<String, dynamic> deletePayload;
  int addStatusCode = 200;
  int deleteStatusCode = 200;
  bool deleteRedirectFirst = false;
  bool deleteRedirectAlways = false;
  bool deleteEmptyBody = false;
  bool addEmptyBody = false;

  final List<String> requestedMethods = [];
  final List<String> requestedPaths = [];
  final List<Object?> requestedBodies = [];
  int addCalls = 0;
  int deleteCalls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    requestedMethods.add(options.method);
    requestedPaths.add(path);
    requestedBodies.add(options.data);
    if (path == _addPath) {
      addCalls++;
      if (addEmptyBody) {
        return ResponseBody.fromString(
          '',
          addStatusCode,
          headers: {Headers.contentTypeHeader: ['application/json']},
        );
      }
      return _json(addPayload, statusCode: addStatusCode);
    }
    if (path == _deletePath) {
      deleteCalls++;
      if (deleteRedirectAlways || (deleteRedirectFirst && deleteCalls == 1)) {
        return ResponseBody.fromString(
          '',
          307,
          headers: {
            HttpHeaders.locationHeader: [
              'https://zh.z-library.sk$_deletePath',
            ],
          },
        );
      }
      if (deleteEmptyBody) {
        return ResponseBody.fromString(
          '',
          deleteStatusCode,
          headers: {Headers.contentTypeHeader: ['application/json']},
        );
      }
      return _json(deletePayload, statusCode: deleteStatusCode);
    }
    return _json({'success': 0, 'error': 'not found'}, statusCode: 404);
  }

  ResponseBody _json(Map<String, dynamic> payload, {int statusCode = 200}) {
    return ResponseBody.fromString(
      jsonEncode(payload),
      statusCode,
      headers: {Headers.contentTypeHeader: ['application/json']},
    );
  }

  @override
  void close({bool force = false}) {}
}

ZLibraryApi _apiWith(_FakeAdapter adapter) {
  return ZLibraryApi(dio: Dio()..httpClientAdapter = adapter);
}

void main() {
  test('add sends a body-less GET to the add-book URL', () async {
    final adapter = _FakeAdapter();
    final api = _apiWith(adapter);

    final response = await api.addBookToBooklist(
      booklistId: _booklistId,
      bookId: _bookId,
    );

    expect(response.success, isTrue);
    expect(response.data, isTrue);
    expect(adapter.addCalls, 1);
    expect(adapter.requestedMethods, ['GET']);
    expect(adapter.requestedPaths, [_addPath]);
    expect(adapter.requestedBodies, [isNull]);
  });

  test('add success:0 with an error fails with that error', () async {
    final adapter = _FakeAdapter(
      addPayload: {'success': 0, 'error': 'booklist not found'},
    );
    final api = _apiWith(adapter);

    final response = await api.addBookToBooklist(
      booklistId: _booklistId,
      bookId: _bookId,
    );

    expect(response.success, isFalse);
    expect(response.error, 'booklist not found');
  });

  test('add empty body fails instead of counting as added', () async {
    final adapter = _FakeAdapter()..addEmptyBody = true;
    final api = _apiWith(adapter);

    final response = await api.addBookToBooklist(
      booklistId: _booklistId,
      bookId: _bookId,
    );

    expect(response.success, isFalse);
  });

  test('add 404 JSON error fails with the server message', () async {
    final adapter = _FakeAdapter(
      addPayload: {'success': 0, 'error': 'not found'},
    )..addStatusCode = 404;
    final api = _apiWith(adapter);

    final response = await api.addBookToBooklist(
      booklistId: _booklistId,
      bookId: _bookId,
    );

    expect(response.success, isFalse);
    expect(response.error, 'not found');
  });

  test('delete follows the 307 to the same URL, then succeeds', () async {
    final adapter = _FakeAdapter()..deleteRedirectFirst = true;
    final api = _apiWith(adapter);

    final response = await api.deleteBooklist(_deleteListId);

    expect(response.success, isTrue);
    expect(response.data, isTrue);
    expect(adapter.deleteCalls, 2);
    expect(adapter.requestedMethods, ['GET', 'GET']);
    expect(adapter.requestedPaths, [_deletePath, _deletePath]);
  });

  test('delete final 2xx with an empty body counts as deleted', () async {
    final adapter = _FakeAdapter()..deleteEmptyBody = true;
    final api = _apiWith(adapter);

    final response = await api.deleteBooklist(_deleteListId);

    expect(response.success, isTrue);
    expect(adapter.deleteCalls, 1);
  });

  test('delete success:0 fails with the server error', () async {
    final adapter = _FakeAdapter(
      deletePayload: {'success': 0, 'error': 'booklist not found'},
    );
    final api = _apiWith(adapter);

    final response = await api.deleteBooklist(_deleteListId);

    expect(response.success, isFalse);
    expect(response.error, 'booklist not found');
  });

  test('delete that keeps redirecting fails instead of looping', () async {
    final adapter = _FakeAdapter()..deleteRedirectAlways = true;
    final api = _apiWith(adapter);

    final response = await api.deleteBooklist(_deleteListId);

    expect(response.success, isFalse);
    expect(response.error, 'too many redirects');
    expect(adapter.deleteCalls, 5);
  });
}
