import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

// Booklist add/remove/delete endpoint tests, all confirmed by packet
// captures on 2026-11-09 (Firefox, zh.z-library.sk):
// - Add: `GET /papi/booklist/{booklistId}/add-book/{bookId}`, HTTP 200
//   with `{"success": 1, "book": {"readlist_id": <booklistId>,
//   "book_id": "<bookId>", "date": "..."}}`. No request body (GET).
// - Remove: `GET /papi/booklist/{booklistId}/remove-book/{readlistBookId}`,
//   HTTP 200 with `{"success": 1}`. No request body (GET). A separate
//   endpoint, NOT a toggle of add-book. The id is the readlist ENTRY id
//   (the per-(book, list) membership-row id), NOT the book id: the
//   website's own remove for list 4096101 sent 161286730, and 白鹿原
//   (book 11959979) in 001 carries `readlistBookId` 161213534.
// - Entry id: `GET /papi/booklist/current-user/{bookId}`, HTTP 200
//   with `{"success": 1, "list": [...]}`; each entry carries the list
//   `id` plus `readlistBookId` (null when the book is not in that list).
// - Delete: `GET /papi/booklist/{booklistId}/delete`. The first
//   response is 307 to the same URL with a `__diamwall` set-cookie
//   (the DDoS-Guard challenge); the list was gone from the profile
//   BOOKLISTS tab afterwards. The final response body was never
//   observed, so the implementation counts a final 2xx with an empty
//   body as success (same precedent as createBooklist) and a final
//   JSON body must carry success: 1.

const _booklistId = 4090055;
const _bookId = 18337950;
const _addPath = '/papi/booklist/$_booklistId/add-book/$_bookId';
const _removeListId = 4096101;
const _removeEntryId = 161286730;
const _removePath =
    '/papi/booklist/$_removeListId/remove-book/$_removeEntryId';
const _currentUserBookId = 11959979;
const _currentUserPath = '/papi/booklist/current-user/$_currentUserBookId';
const _currentUserListId = 4088695;
const _currentUserEntryId = 161213534;

/// One current-user entry, shaped like the live 2026-11-09 response for
/// 白鹿原 (book 11959979): the list `id` plus `readlistBookId`, null when
/// the book is not in that list.
Map<String, dynamic> _currentUserEntry({
  required Object? id,
  required Object? readlistBookId,
  String title = '',
}) {
  return {
    'id': id,
    'user_id': 35899435,
    'title': title,
    'description': '',
    'languages': null,
    'public': true,
    'adult': false,
    'editors_choice': false,
    'views_count': 0,
    'books_count': 0,
    'favorites_count': 0,
    'comments_count': 0,
    'color': 0,
    'date_updated': '2026-11-09T11:49:26.000000Z',
    'date': '2026-11-09T09:35:36.000000Z',
    'readlistBookId': readlistBookId,
  };
}
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
    this.removePayload = const {'success': 1},
    this.currentUserPayload = const {
      'success': 1,
      'list': [
        {'id': 4096101, 'readlistBookId': null},
        {'id': 4090055, 'readlistBookId': null},
        {'id': 4088695, 'readlistBookId': 161213534},
      ],
    },
  });

  Map<String, dynamic> addPayload;
  Map<String, dynamic> deletePayload;
  Map<String, dynamic> removePayload;
  Map<String, dynamic> currentUserPayload;
  int addStatusCode = 200;
  int deleteStatusCode = 200;
  int removeStatusCode = 200;
  int currentUserStatusCode = 200;
  bool deleteRedirectFirst = false;
  bool deleteRedirectAlways = false;
  bool deleteEmptyBody = false;
  bool removeRedirectFirst = false;
  bool removeRedirectAlways = false;
  bool removeEmptyBody = false;
  bool addEmptyBody = false;

  final List<String> requestedMethods = [];
  final List<String> requestedPaths = [];
  final List<Object?> requestedBodies = [];
  int addCalls = 0;
  int deleteCalls = 0;
  int removeCalls = 0;
  int currentUserCalls = 0;

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
    if (path == _currentUserPath) {
      currentUserCalls++;
      return _json(currentUserPayload, statusCode: currentUserStatusCode);
    }
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
    if (path == _removePath) {
      removeCalls++;
      if (removeRedirectAlways || (removeRedirectFirst && removeCalls == 1)) {
        return ResponseBody.fromString(
          '',
          307,
          headers: {
            HttpHeaders.locationHeader: [
              'https://zh.z-library.sk$_removePath',
            ],
          },
        );
      }
      if (removeEmptyBody) {
        return ResponseBody.fromString(
          '',
          removeStatusCode,
          headers: {Headers.contentTypeHeader: ['application/json']},
        );
      }
      return _json(removePayload, statusCode: removeStatusCode);
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

  test('remove sends a body-less GET to the remove-book URL', () async {
    final adapter = _FakeAdapter();
    final api = _apiWith(adapter);

    final response = await api.removeBookFromBooklist(
      booklistId: _removeListId,
      readlistBookId: _removeEntryId,
    );

    expect(response.success, isTrue);
    expect(response.data, isTrue);
    expect(adapter.removeCalls, 1);
    expect(adapter.requestedMethods, ['GET']);
    expect(adapter.requestedPaths, [_removePath]);
    expect(adapter.requestedBodies, [isNull]);
  });

  test('remove success:0 fails with the server error', () async {
    final adapter = _FakeAdapter(
      removePayload: {'success': 0, 'error': 'book not in list'},
    );
    final api = _apiWith(adapter);

    final response = await api.removeBookFromBooklist(
      booklistId: _removeListId,
      readlistBookId: _removeEntryId,
    );

    expect(response.success, isFalse);
    expect(response.error, 'book not in list');
  });

  test('remove final 2xx with an empty body counts as removed', () async {
    final adapter = _FakeAdapter()..removeEmptyBody = true;
    final api = _apiWith(adapter);

    final response = await api.removeBookFromBooklist(
      booklistId: _removeListId,
      readlistBookId: _removeEntryId,
    );

    expect(response.success, isTrue);
    expect(adapter.removeCalls, 1);
  });

  test('remove follows the 307 to the same URL, then succeeds', () async {
    final adapter = _FakeAdapter()..removeRedirectFirst = true;
    final api = _apiWith(adapter);

    final response = await api.removeBookFromBooklist(
      booklistId: _removeListId,
      readlistBookId: _removeEntryId,
    );

    expect(response.success, isTrue);
    expect(adapter.removeCalls, 2);
    expect(adapter.requestedMethods, ['GET', 'GET']);
    expect(adapter.requestedPaths, [_removePath, _removePath]);
  });

  test('current-user returns the entry id for the target list', () async {
    final adapter = _FakeAdapter(
      currentUserPayload: {
        'success': 1,
        'list': [
          _currentUserEntry(id: 4096101, readlistBookId: null, title: '嘎嘎嘎'),
          _currentUserEntry(id: 4090055, readlistBookId: null, title: '555'),
          _currentUserEntry(
            id: _currentUserListId,
            readlistBookId: _currentUserEntryId,
            title: '001',
          ),
        ],
      },
    );
    final api = _apiWith(adapter);

    final response = await api.getReadlistBookId(
      booklistId: _currentUserListId,
      bookId: _currentUserBookId,
    );

    expect(response.success, isTrue);
    expect(response.data, _currentUserEntryId);
    expect(adapter.currentUserCalls, 1);
    expect(adapter.requestedMethods, ['GET']);
    expect(adapter.requestedPaths, [_currentUserPath]);
    expect(adapter.requestedBodies, [isNull]);
  });

  test('current-user returns null when the book is not in the list',
      () async {
    final adapter = _FakeAdapter();
    final api = _apiWith(adapter);

    final response = await api.getReadlistBookId(
      booklistId: 4090055,
      bookId: _currentUserBookId,
    );

    expect(response.success, isTrue);
    expect(response.data, isNull);
  });

  test('current-user returns null when the target list is absent',
      () async {
    final adapter = _FakeAdapter(
      currentUserPayload: {
        'success': 1,
        'list': [
          _currentUserEntry(id: 4096101, readlistBookId: null),
        ],
      },
    );
    final api = _apiWith(adapter);

    final response = await api.getReadlistBookId(
      booklistId: _currentUserListId,
      bookId: _currentUserBookId,
    );

    expect(response.success, isTrue);
    expect(response.data, isNull);
  });

  test('current-user accepts the entry id as a numeric string', () async {
    final adapter = _FakeAdapter(
      currentUserPayload: {
        'success': 1,
        'list': [
          _currentUserEntry(
            id: '$_currentUserListId',
            readlistBookId: '$_currentUserEntryId',
          ),
        ],
      },
    );
    final api = _apiWith(adapter);

    final response = await api.getReadlistBookId(
      booklistId: _currentUserListId,
      bookId: _currentUserBookId,
    );

    expect(response.success, isTrue);
    expect(response.data, _currentUserEntryId);
  });

  test('current-user non-success JSON fails with the server error', () async {
    final adapter = _FakeAdapter(
      currentUserPayload: {'success': 0, 'error': 'not found'},
    );
    final api = _apiWith(adapter);

    final response = await api.getReadlistBookId(
      booklistId: _currentUserListId,
      bookId: _currentUserBookId,
    );

    expect(response.success, isFalse);
    expect(response.error, 'not found');
  });
}
