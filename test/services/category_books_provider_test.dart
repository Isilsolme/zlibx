import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';
import 'package:zlibx/providers/category_books_provider.dart';
import 'package:zlibx/providers/zlibrary_provider.dart';

/// [CategoryBooksController] pagination tests.
///
/// The P0 fix: a category page carries 50 cards, not 10 — the old
/// `books.length == 10` rule set `hasMore` false on a full first
/// page and pages 2–10 were unreachable. `hasMore` now comes from
/// the page's `pagerOptions.pagesTotal` when present; without one,
/// the first page's card count is the effective page size.
///
/// fake only implements the methods this controller path uses
/// (the two fetches plus the two URL builders `_loadPage` passes
/// to the solver fallback); any other call throws.
class _FakeZLibraryApi implements ZLibraryApi {
  _FakeZLibraryApi({required this.browsePages, this.searchPages = const {}});

  final Map<int, CategoryPage> browsePages;
  final Map<int, CategoryPage> searchPages;

  int browseCalls = 0;
  int searchCalls = 0;
  String? lastBrowseOrder;
  String? lastSearchQuery;
  String? lastSearchOrder;
  String? lastSearchSlug;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unexpected: ${invocation.memberName}');

  @override
  String categoryPageUrl(int categoryId, {int page = 1, String? order}) =>
      'https://example.com/category/$categoryId';

  @override
  String categorySearchUrl({
    required int categoryId,
    String? slug,
    required String query,
    bool exact = false,
    int? yearFrom,
    int? yearTo,
    List<String>? languages,
    List<String>? extensions,
    List<String>? contentTypes,
    String? order,
    int page = 1,
  }) => 'https://example.com/category/$categoryId/s/?q=$query';

  @override
  Future<ApiResponse<CategoryPage>> getCategoryBooks(
    int categoryId, {
    int page = 1,
    String? order,
  }) async {
    browseCalls++;
    lastBrowseOrder = order;
    return ApiResponse.ok(browsePages[page] ?? const CategoryPage(books: []));
  }

  @override
  Future<ApiResponse<CategoryPage>> searchInCategory({
    required int categoryId,
    String? slug,
    required String query,
    bool exact = false,
    int? yearFrom,
    int? yearTo,
    List<String>? languages,
    List<String>? extensions,
    List<String>? contentTypes,
    String? order,
    int page = 1,
  }) async {
    searchCalls++;
    lastSearchQuery = query;
    lastSearchOrder = order;
    lastSearchSlug = slug;
    return ApiResponse.ok(searchPages[page] ?? const CategoryPage(books: []));
  }
}

/// A synthetic page of [count] books (ids [startId] + 1 .. + count),
/// optionally carrying a [totalPages] from `pagerOptions`.
CategoryPage _page({required int count, int? totalPages, int startId = 90000}) {
  return CategoryPage(
    books: [
      for (var i = 1; i <= count; i++)
        CategoryBook(
          book: Book(id: startId + i, title: 'Synthetic Book $i'),
        ),
    ],
    totalPages: totalPages,
  );
}

const _args = CategoryBooksArgs(
  categoryId: 528,
  categoryName: 'Synthetic Category',
);

/// Loads the controller with the fake pages and waits for the
/// microtask-started loadFirst to finish.
Future<ProviderContainer> _loadedContainer(_FakeZLibraryApi api) async {
  final container = ProviderContainer(
    overrides: [zlibraryApiProvider.overrideWithValue(api)],
  );
  addTearDown(container.dispose);
  // A listener keeps the autoDispose controller alive for the test.
  container.listen(categoryBooksControllerProvider(_args), (_, _) {});
  await Future<void>.delayed(const Duration(milliseconds: 100));
  return container;
}

CategoryBooksState _state(ProviderContainer container) =>
    container.read(categoryBooksControllerProvider(_args));

void main() {
  test('50-book first page with a total has more', () async {
    final api = _FakeZLibraryApi(
      browsePages: {1: _page(count: 50, totalPages: 10)},
    );
    final container = await _loadedContainer(api);
    final state = _state(container);
    expect(state.books.length, 50);
    expect(state.hasMore, isTrue);
    expect(state.nextPage, 2);
    expect(state.totalPages, 10);
    expect(state.effectivePageSize, 50);
    expect(state.error, isNull);
  });

  test('loadMore respects totalPages', () async {
    final api = _FakeZLibraryApi(
      browsePages: {
        1: _page(count: 50, totalPages: 2),
        2: _page(count: 50, totalPages: 2, startId: 90100),
      },
    );
    final container = await _loadedContainer(api);
    await container
        .read(categoryBooksControllerProvider(_args).notifier)
        .loadMore();
    final state = _state(container);
    expect(state.books.length, 100);
    expect(state.hasMore, isFalse);
    expect(state.nextPage, 3);
  });

  test('without a total, the first page count is the page size', () async {
    final api = _FakeZLibraryApi(
      browsePages: {
        1: _page(count: 50),
        2: _page(count: 50, startId: 90100),
        3: _page(count: 12, startId: 90200),
      },
    );
    final container = await _loadedContainer(api);
    final notifier = container.read(
      categoryBooksControllerProvider(_args).notifier,
    );
    expect(_state(container).hasMore, isTrue);
    await notifier.loadMore();
    expect(_state(container).books.length, 100);
    expect(_state(container).hasMore, isTrue);
    await notifier.loadMore();
    expect(_state(container).books.length, 112);
    expect(_state(container).hasMore, isFalse);
  });

  test('out-of-range page adds no duplicates', () async {
    final samePage = _page(count: 50, totalPages: 10);
    final api = _FakeZLibraryApi(browsePages: {1: samePage, 2: samePage});
    final container = await _loadedContainer(api);
    await container
        .read(categoryBooksControllerProvider(_args).notifier)
        .loadMore();
    expect(_state(container).books.length, 50);
    // The total still says more pages exist; the dedupe is the
    // safety net, not the hasMore rule.
    expect(_state(container).hasMore, isTrue);
  });

  test('empty first page has no more', () async {
    final api = _FakeZLibraryApi(browsePages: {1: _page(count: 0)});
    final container = await _loadedContainer(api);
    expect(_state(container).books, isEmpty);
    expect(_state(container).hasMore, isFalse);
  });

  test(
    'search routes to searchInCategory, clearing returns to browse',
    () async {
      final api = _FakeZLibraryApi(
        browsePages: {1: _page(count: 50, totalPages: 10)},
        searchPages: {1: _page(count: 3, totalPages: 1)},
      );
      final container = await _loadedContainer(api);
      final notifier = container.read(
        categoryBooksControllerProvider(_args).notifier,
      );
      expect(api.browseCalls, 1);
      notifier.search('synthetic');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(api.searchCalls, 1);
      expect(api.lastSearchQuery, 'synthetic');
      expect(_state(container).books.length, 3);
      expect(_state(container).query, 'synthetic');
      notifier.search('');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      // 3 browses: the initial load, the slug resolution that the search
      // needed (this page carries no search form), and the browse the
      // cleared query returns to.
      expect(api.browseCalls, 3);
      expect(_state(container).query, '');
      expect(_state(container).books.length, 50);
    },
  );

  test('in-category search carries the browse page search slug', () async {
    // The server only serves /category/{id}/{slug}/s/; the bare search
    // URL answers an empty page. The slug comes from the browse page's
    // own search form, never hand-built.
    final api = _FakeZLibraryApi(
      browsePages: {
        1: CategoryPage(
          books: _page(count: 2, totalPages: 3).books,
          totalPages: 3,
          searchSlug: 'Psychology-Theory-History',
        ),
      },
      searchPages: {1: _page(count: 3, totalPages: 1)},
    );
    final container = await _loadedContainer(api);
    container
        .read(categoryBooksControllerProvider(_args).notifier)
        .search('freud');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(api.searchCalls, 1);
    expect(api.lastSearchSlug, 'Psychology-Theory-History');
  });

  test('setOrder passes the order through and reloads', () async {
    final api = _FakeZLibraryApi(
      browsePages: {1: _page(count: 50, totalPages: 10)},
    );
    final container = await _loadedContainer(api);
    final notifier = container.read(
      categoryBooksControllerProvider(_args).notifier,
    );
    expect(api.lastBrowseOrder, 'popular');
    notifier.setOrder('titleA');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(api.lastBrowseOrder, 'titleA');
    expect(_state(container).order, 'titleA');
    expect(_state(container).books.length, 50);
  });
}
