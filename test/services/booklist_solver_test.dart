import 'package:flutter_test/flutter_test.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';
import 'package:zlibx/providers/booklist_detail_provider.dart';
import 'package:zlibx/providers/booklists_provider.dart';
import 'package:zlibx/services/booklist_solver.dart';

Booklist _list(String id) =>
    Booklist(id: id, name: 'list $id', url: 'https://z.example/booklist/$id');

void main() {
  group('BooklistSolver.isChallengeError', () {
    test('recognises the browser-check wall shapes', () {
      expect(BooklistSolver.isChallengeError('HTTP 503: browser check page'), isTrue);
      expect(BooklistSolver.isChallengeError('Checking your browser'), isTrue);
      expect(BooklistSolver.isChallengeError('DDoS-Guard'), isTrue);
      expect(BooklistSolver.isChallengeError('cf_blocked'), isTrue);
    });

    test('ignores ordinary errors and null', () {
      expect(BooklistSolver.isChallengeError(null), isFalse);
      expect(BooklistSolver.isChallengeError('HTTP 404'), isFalse);
    });
  });

  test('BooklistDetailArgs compares by list id', () {
    expect(
      BooklistDetailArgs(booklist: _list('1')),
      BooklistDetailArgs(booklist: _list('1')),
    );
    expect(
      BooklistDetailArgs(booklist: _list('1')) ==
          BooklistDetailArgs(booklist: _list('2')),
      isFalse,
    );
  });

  test('BooklistsState.copyWith keeps fields and can clear the error', () {
    final failed = const BooklistsState().copyWith(
      phase: BooklistsPhase.error,
      error: 'boom',
    );
    expect(failed.error, 'boom');
    expect(failed.copyWith(isLoadingMore: true).error, 'boom');
    expect(failed.copyWith(clearError: true).error, isNull);
    expect(failed.tab, BooklistTab.mine);
  });

  test('BooklistDetailState.copyWith can clear the error', () {
    final failed = const BooklistDetailState().copyWith(error: 'boom');
    expect(failed.copyWith(isLoading: false).error, 'boom');
    expect(failed.copyWith(clearError: true).error, isNull);
  });
}
