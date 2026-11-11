import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

// Booklist write-endpoint tests for the booklists batch (all ids, titles
// and hashes below are SYNTHETIC — no real user data):
// - Create: `POST /papi/booklist/create` with `{title, description}`
//   plus optional `color` / `private` / `bookId`; the site answers
//   `{readlist: {id, title, hash, ...}}` (its form reads
//   `response.readlist`), and the parser tries `readlist` first. A
//   2xx with an empty body still counts as created (the 2026-11-07
//   capture), with null data.
// - Add entry: `GET /papi/booklist/{id}/add-book/{bookId}` returns the
//   membership-row id from `book.readlist_id` first, else `book.id`
//   (which field carries it is UNCONFIRMED — the 2026-11-09 capture
//   showed `readlist_id`, the site's picker reads `book.id`).
// - Memberships: `GET /papi/booklist/current-user/{bookId}` answers
//   `{success: 1, list: [{id, title, readlistBookId}]}`.
// - Edit: `POST /papi/booklist/{id}/edit` with `{title, description,
//   private, color}`; the answer carries `{readlist: {...}}`.
// - Color: `GET /papi/booklist/{id}/color/{0..5}`. Public toggle:
//   `GET /papi/booklist/{id}/public`. Favorite: `POST
//   /papi/booklist/{id}/favorite/add`; unfavorite: `DELETE
//   /papi/booklist/{id}/favorite/remove`.
// - Note: `POST /papi/booklist/{id}/save-description/{entryId}` with
//   `{bookDescription}`; an empty note is sent as a single space.
// - Recommendations: `POST /papi/booklist/get-from-category` with
//   `{categoryId: '', languages: 'false', booklistsCount: N}`; the
//   answer's `html` array carries one JSON object per list.

const _listId = 1001;
const _bookId = 2002;
const _entryId = 3003;
const _createPath = '/papi/booklist/create';
const _editPath = '/papi/booklist/$_listId/edit';
const _colorPath = '/papi/booklist/$_listId/color/4';
const _publicPath = '/papi/booklist/$_listId/public';
const _favoriteAddPath = '/papi/booklist/$_listId/favorite/add';
const _favoriteRemovePath = '/papi/booklist/$_listId/favorite/remove';
const _saveDescriptionPath =
    '/papi/booklist/$_listId/save-description/$_entryId';
const _recommendationsPath = '/papi/booklist/get-from-category';
const _currentUserPath = '/papi/booklist/current-user/$_bookId';
const _addPath = '/papi/booklist/$_listId/add-book/$_bookId';

/// Serves canned write-endpoint responses so the calls run without a
/// network. Records every request's method, path and body.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({
    this.createPayload = const {
      'success': 1,
      'readlist': {'id': 1001, 'title': 'Test List Alpha', 'hash': 'aa00'},
    },
    this.addPayload = const {
      'success': 1,
      'book': {'readlist_id': 3003, 'book_id': '2002'},
    },
    this.currentUserPayload = const {
      'success': 1,
      'list': [
        {'id': 1001, 'title': 'Test List Alpha', 'readlistBookId': 3003},
        {'id': 1002, 'title': 'Test List Beta', 'readlistBookId': null},
      ],
    },
    this.recommendationsPayload = const {
      'success': 1,
      'html': [
        {
          'id': 5001,
          'href': '/booklist/5001/abc/rec-one.html',
          'title': 'Rec One',
          'author': 'Some Author',
          'authorProfile': '/profile/1/x',
          'quantity': 5,
          'views': '42',
          'comments': '2',
          'color': 3,
        },
        {
          'id': 5002,
          'href': '/booklist/5002/def/rec-two.html',
          'title': 'Rec Two',
          'author': '',
          'quantity': '7',
          'views': '',
        },
      ],
    },
  });

  Map<String, dynamic> createPayload;
  Map<String, dynamic> addPayload;
  Map<String, dynamic> currentUserPayload;
  Map<String, dynamic> recommendationsPayload;
  bool createEmptyBody = false;
  bool editEmptyBody = false;

  final List<String> requestedMethods = [];
  final List<String> requestedPaths = [];
  final List<Object?> requestedBodies = [];

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
    switch (path) {
      case _createPath:
        if (createEmptyBody) {
          return ResponseBody.fromString(
            '',
            200,
            headers: {Headers.contentTypeHeader: ['application/json']},
          );
        }
        return _json(createPayload);
      case _editPath:
        if (editEmptyBody) {
          return ResponseBody.fromString(
            '',
            200,
            headers: {Headers.contentTypeHeader: ['application/json']},
          );
        }
        return _json(const {
          'success': 1,
          'readlist': {'id': 1001, 'title': 'Renamed List', 'hash': 'aa00'},
        });
      case _colorPath:
      case _publicPath:
      case _favoriteAddPath:
      case _favoriteRemovePath:
      case _saveDescriptionPath:
        return _json(const {'success': 1});
      case _recommendationsPath:
        return _json(recommendationsPayload);
      case _currentUserPath:
        return _json(currentUserPayload);
      case _addPath:
        return _json(addPayload);
      default:
        return _json(
          {'success': 0, 'error': 'not found'},
          statusCode: 404,
        );
    }
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
  group('createBooklist', () {
    test('reads the new list from the readlist wrapper', () async {
      final adapter = _FakeAdapter();
      final api = _apiWith(adapter);

      final response = await api.createBooklist(
        title: 'Test List Alpha',
        description: 'desc',
      );

      expect(response.success, isTrue);
      expect(response.data?.id, '1001');
      expect(response.data?.name, 'Test List Alpha');
      expect(adapter.requestedMethods, ['POST']);
      expect(adapter.requestedPaths, [_createPath]);
      final body = jsonDecode(adapter.requestedBodies.single as String)
          as Map<String, dynamic>;
      expect(body['title'], 'Test List Alpha');
      expect(body['description'], 'desc');
      expect(body.containsKey('color'), isFalse);
      expect(body.containsKey('private'), isFalse);
      expect(body.containsKey('bookId'), isFalse);
    });

    test('sends color, private and bookId when given', () async {
      final adapter = _FakeAdapter();
      final api = _apiWith(adapter);

      final response = await api.createBooklist(
        title: 'T',
        color: 4,
        isPrivate: true,
        bookId: _bookId,
      );

      expect(response.success, isTrue);
      final body = jsonDecode(adapter.requestedBodies.single as String)
          as Map<String, dynamic>;
      expect(body['color'], 4);
      expect(body['private'], isTrue);
      expect(body['bookId'], _bookId);
    });

    test('empty-body 2xx still counts as created with null data', () async {
      final adapter = _FakeAdapter()..createEmptyBody = true;
      final api = _apiWith(adapter);

      final response = await api.createBooklist(title: 'T');

      expect(response.success, isTrue);
      expect(response.data, isNull);
    });

    test('empty title fails without a request', () async {
      final adapter = _FakeAdapter();
      final api = _apiWith(adapter);

      final response = await api.createBooklist(title: '  ');

      expect(response.success, isFalse);
      expect(adapter.requestedPaths, isEmpty);
    });
  });

  group('addBookToBooklistEntry', () {
    test('returns readlist_id from the book map', () async {
      final adapter = _FakeAdapter();
      final api = _apiWith(adapter);

      final response = await api.addBookToBooklistEntry(
        booklistId: _listId,
        bookId: _bookId,
      );

      expect(response.success, isTrue);
      expect(response.data, _entryId);
      expect(adapter.requestedMethods, ['GET']);
      expect(adapter.requestedPaths, [_addPath]);
    });

    test('falls back to book.id when readlist_id is absent', () async {
      final adapter = _FakeAdapter(
        addPayload: const {
          'success': 1,
          'book': {'id': 3004, 'book_id': '2002'},
        },
      );
      final api = _apiWith(adapter);

      final response = await api.addBookToBooklistEntry(
        booklistId: _listId,
        bookId: _bookId,
      );

      expect(response.success, isTrue);
      expect(response.data, 3004);
    });

    test('null entry id when the response carries neither', () async {
      final adapter = _FakeAdapter(
        addPayload: const {
          'success': 1,
          'book': {'book_id': '2002'},
        },
      );
      final api = _apiWith(adapter);

      final response = await api.addBookToBooklistEntry(
        booklistId: _listId,
        bookId: _bookId,
      );

      expect(response.success, isTrue);
      expect(response.data, isNull);
    });
  });

  group('getBooklistsForBook', () {
    test('parses memberships with member flags', () async {
      final adapter = _FakeAdapter();
      final api = _apiWith(adapter);

      final response = await api.getBooklistsForBook(_bookId);

      expect(response.success, isTrue);
      final lists = response.data!;
      expect(lists.length, 2);
      expect(lists[0].booklistId, 1001);
      expect(lists[0].title, 'Test List Alpha');
      expect(lists[0].isMember, isTrue);
      expect(lists[0].readlistBookId, _entryId);
      expect(lists[1].booklistId, 1002);
      expect(lists[1].isMember, isFalse);
      expect(lists[1].readlistBookId, isNull);
      expect(adapter.requestedMethods, ['GET']);
      expect(adapter.requestedPaths, [_currentUserPath]);
    });
  });

  group('editBooklist', () {
    test('posts title, description, private and color', () async {
      final adapter = _FakeAdapter();
      final api = _apiWith(adapter);

      final response = await api.editBooklist(
        id: _listId,
        title: 'Renamed List',
        description: 'new desc',
        isPrivate: true,
        color: 2,
      );

      expect(response.success, isTrue);
      expect(response.data?.id, '1001');
      expect(response.data?.name, 'Renamed List');
      expect(adapter.requestedMethods, ['POST']);
      expect(adapter.requestedPaths, [_editPath]);
      final body = jsonDecode(adapter.requestedBodies.single as String)
          as Map<String, dynamic>;
      expect(body, {
        'title': 'Renamed List',
        'description': 'new desc',
        'private': true,
        'color': 2,
      });
    });

    test('empty-body 2xx counts as edited with null data', () async {
      final adapter = _FakeAdapter()..editEmptyBody = true;
      final api = _apiWith(adapter);

      final response = await api.editBooklist(id: _listId, title: 'T');

      expect(response.success, isTrue);
      expect(response.data, isNull);
    });
  });

  group('color / public / favorite', () {
    test('setBooklistColor GETs the color URL', () async {
      final adapter = _FakeAdapter();
      final api = _apiWith(adapter);

      final response = await api.setBooklistColor(id: _listId, color: 4);

      expect(response.success, isTrue);
      expect(response.data, isTrue);
      expect(adapter.requestedMethods, ['GET']);
      expect(adapter.requestedPaths, [_colorPath]);
    });

    test('toggleBooklistPublic GETs the public URL', () async {
      final adapter = _FakeAdapter();
      final api = _apiWith(adapter);

      final response = await api.toggleBooklistPublic(_listId);

      expect(response.success, isTrue);
      expect(adapter.requestedMethods, ['GET']);
      expect(adapter.requestedPaths, [_publicPath]);
    });

    test('favoriteBooklist POSTs with an empty JSON body', () async {
      final adapter = _FakeAdapter();
      final api = _apiWith(adapter);

      final response = await api.favoriteBooklist(_listId);

      expect(response.success, isTrue);
      expect(adapter.requestedMethods, ['POST']);
      expect(adapter.requestedPaths, [_favoriteAddPath]);
      expect(adapter.requestedBodies.single, '{}');
    });

    test('unfavoriteBooklist DELETEs the favorite URL', () async {
      final adapter = _FakeAdapter();
      final api = _apiWith(adapter);

      final response = await api.unfavoriteBooklist(_listId);

      expect(response.success, isTrue);
      expect(adapter.requestedMethods, ['DELETE']);
      expect(adapter.requestedPaths, [_favoriteRemovePath]);
    });
  });

  group('saveBookDescription', () {
    test('posts the note for the entry id', () async {
      final adapter = _FakeAdapter();
      final api = _apiWith(adapter);

      final response = await api.saveBookDescription(
        listId: _listId,
        entryId: _entryId,
        description: 'read this first',
      );

      expect(response.success, isTrue);
      expect(adapter.requestedMethods, ['POST']);
      expect(adapter.requestedPaths, [_saveDescriptionPath]);
      final body = jsonDecode(adapter.requestedBodies.single as String)
          as Map<String, dynamic>;
      expect(body, {'bookDescription': 'read this first'});
    });

    test('an empty note is sent as a single space', () async {
      final adapter = _FakeAdapter();
      final api = _apiWith(adapter);

      final response = await api.saveBookDescription(
        listId: _listId,
        entryId: _entryId,
        description: '',
      );

      expect(response.success, isTrue);
      final body = jsonDecode(adapter.requestedBodies.single as String)
          as Map<String, dynamic>;
      expect(body, {'bookDescription': ' '});
    });
  });

  group('getRecommendedBooklists', () {
    test('posts the slot request and parses the html array', () async {
      final adapter = _FakeAdapter();
      final api = _apiWith(adapter);

      final response = await api.getRecommendedBooklists(booklistsCount: 10);

      expect(response.success, isTrue);
      expect(adapter.requestedMethods, ['POST']);
      expect(adapter.requestedPaths, [_recommendationsPath]);
      final body = jsonDecode(adapter.requestedBodies.single as String)
          as Map<String, dynamic>;
      expect(body, {
        'categoryId': '',
        'languages': 'false',
        'booklistsCount': 10,
      });
      final lists = response.data!;
      expect(lists.length, 2);
      expect(lists[0].id, '5001');
      expect(lists[0].name, 'Rec One');
      expect(lists[0].author, 'Some Author');
      expect(lists[0].authorProfile, '/profile/1/x');
      expect(lists[0].count, 5);
      expect(lists[0].views, '42');
      expect(lists[0].comments, '2');
      expect(lists[0].color, 3);
      expect(lists[0].url, endsWith('/booklist/5001/abc/rec-one.html'));
      expect(lists[1].id, '5002');
      expect(lists[1].count, 7);
    });
  });
}
