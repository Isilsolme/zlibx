import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

// Delete-comment endpoint tests: `DELETE
// /papi/comments/delete/{commentId}`, confirmed by a packet capture on
// 2026-11-09 (Firefox, zh.z-library.sk): HTTP 200 with
// `{"success": 1}`. The capture's Payload tab was not shown, so the
// implementation sends no request body — these tests pin that: the
// recorded request must be a DELETE with null data.

const _commentId = 1046367;
const _deletePath = '/papi/comments/delete/$_commentId';

/// Serves canned delete responses so the call runs without a network.
/// Records every request's method, path and body.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({this.deletePayload = const {'success': 1}});

  Map<String, dynamic> deletePayload;
  int deleteStatusCode = 200;
  bool redirectFirst = false;
  bool emptyBody = false;

  final List<String> requestedMethods = [];
  final List<String> requestedPaths = [];
  final List<Object?> requestedBodies = [];
  int deleteCalls = 0;

  _FakeAdapter.withStatus(this.deletePayload, this.deleteStatusCode);

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
    if (path == _deletePath) {
      deleteCalls++;
      if (redirectFirst && deleteCalls == 1) {
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
      if (emptyBody) {
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
  test('delete sends a body-less DELETE to the id-in-path URL', () async {
    final adapter = _FakeAdapter();
    final api = _apiWith(adapter);

    final response = await api.deleteBookComment(_commentId);

    expect(response.success, isTrue);
    expect(response.data, isTrue);
    expect(adapter.deleteCalls, 1);
    expect(adapter.requestedMethods, ['DELETE']);
    expect(adapter.requestedPaths, [_deletePath]);
    expect(adapter.requestedBodies, [isNull]);
  });

  test('success:0 with an error fails with that error', () async {
    final adapter = _FakeAdapter(
      deletePayload: {'success': 0, 'error': 'comment not found'},
    );
    final api = _apiWith(adapter);

    final response = await api.deleteBookComment(_commentId);

    expect(response.success, isFalse);
    expect(response.error, 'comment not found');
  });

  test('empty body fails instead of counting as deleted', () async {
    final adapter = _FakeAdapter()..emptyBody = true;
    final api = _apiWith(adapter);

    final response = await api.deleteBookComment(_commentId);

    expect(response.success, isFalse);
  });

  test('307 to the same URL is re-sent as DELETE', () async {
    final adapter = _FakeAdapter()..redirectFirst = true;
    final api = _apiWith(adapter);

    final response = await api.deleteBookComment(_commentId);

    expect(response.success, isTrue);
    expect(adapter.deleteCalls, 2);
    expect(adapter.requestedMethods, ['DELETE', 'DELETE']);
  });

  test('404 JSON error fails with the server message', () async {
    final adapter =
        _FakeAdapter.withStatus({'success': 0, 'error': 'not found'}, 404);
    final api = _apiWith(adapter);

    final response = await api.deleteBookComment(_commentId);

    expect(response.success, isFalse);
    expect(response.error, 'not found');
  });
}
