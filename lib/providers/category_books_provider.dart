import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

import '../services/category_repository.dart';
import 'auth_provider.dart';
import 'zlibrary_provider.dart';

/// Arguments for CategoryBooksScreen. Equality is by category id so
/// the screen's provider family resolves to the same controller on
/// rebuild. The name is display-only (the screen title) and is
/// deliberately excluded from equality.
class CategoryBooksArgs {
  final int categoryId;
  final String categoryName;

  const CategoryBooksArgs({
    required this.categoryId,
    required this.categoryName,
  });

  @override
  bool operator ==(Object other) =>
      other is CategoryBooksArgs && other.categoryId == categoryId;

  @override
  int get hashCode => categoryId.hashCode;
}

class CategoryBooksState {
  /// True only while there is no page to paint yet.
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;
  final List<Book> books;
  final bool hasMore;
  final int nextPage;

  const CategoryBooksState({
    this.isLoading = true,
    this.isLoadingMore = false,
    this.error,
    this.books = const [],
    this.hasMore = true,
    this.nextPage = 2,
  });

  CategoryBooksState copyWith({
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
    bool clearError = false,
    List<Book>? books,
    bool? hasMore,
    int? nextPage,
  }) {
    return CategoryBooksState(
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
      books: books ?? this.books,
      hasMore: hasMore ?? this.hasMore,
      nextPage: nextPage ?? this.nextPage,
    );
  }
}

/// Books in one category. Every page is the category page's own HTML
/// (10 books per page, `?page=N`); there is no JSON endpoint and no
/// persistent cache in v1, so every open revalidates from the network.
/// A short page (fewer than 10 books) means the last page.
class CategoryBooksController
    extends
        AutoDisposeFamilyNotifier<CategoryBooksState, CategoryBooksArgs> {
  /// Books the site renders per category page.
  static const int pageSize = 10;

  final List<Book> _books = [];
  // O(1) membership checks while pages are appended.
  final Set<int> _bookIds = <int>{};

  bool _alive = true;
  int _generation = 0;

  /// Data layer: fetching and parsing (see [CategoryRepository]).
  /// Holds no state of its own; rebuilt on every (re)build from the
  /// shared API instance.
  late CategoryRepository _repository;

  int get _categoryId => arg.categoryId;

  @override
  CategoryBooksState build(CategoryBooksArgs arg) {
    _repository = CategoryRepository(ref.read(zlibraryApiProvider));
    _alive = true;
    ref.onDispose(() => _alive = false);
    Future<void>.microtask(loadFirst);
    return const CategoryBooksState();
  }

  bool _isCurrent(int generation) => _alive && generation == _generation;

  Future<void> loadFirst() async {
    if (!_alive) return;
    final generation = ++_generation;
    _books.clear();
    _bookIds.clear();
    state = const CategoryBooksState();
    final result = await _loadPage(1, generation: generation);
    if (!_isCurrent(generation)) return;
    final books = result.books;
    if (books == null) {
      state = state.copyWith(
        error: result.error ?? 'Failed to load category',
        isLoading: false,
      );
      return;
    }
    _merge(books);
    state = state.copyWith(
      books: List.of(_books),
      hasMore: books.length == pageSize,
      nextPage: 2,
      isLoading: false,
    );
  }

  /// Load-more for page 2 and up. A failed later page must not
  /// silently end the list: a network blip would look like "no more
  /// books" with no way back. Keep hasMore so the next scroll event
  /// re-enters loadMore and retries.
  Future<void> loadMore() async {
    final s = state;
    if (!_alive ||
        s.isLoading ||
        s.isLoadingMore ||
        !s.hasMore ||
        s.error != null) {
      return;
    }
    final page = s.nextPage;
    final generation = _generation;
    state = state.copyWith(isLoadingMore: true);
    final result = await _loadPage(page, generation: generation);
    if (!_isCurrent(generation)) return;
    final books = result.books;
    if (books == null) {
      state = state.copyWith(isLoadingMore: false);
      return;
    }
    _merge(books);
    state = state.copyWith(
      books: List.of(_books),
      hasMore: books.length == pageSize,
      nextPage: page + 1,
      isLoadingMore: false,
    );
  }

  /// Loads one page: Dio first, the WebView solver on the
  /// browser-check wall. Returns the books, or null books + an error
  /// message when both paths failed.
  Future<({List<Book>? books, String? error})> _loadPage(
    int page, {
    required int generation,
  }) async {
    final url = _repository.categoryPageUrl(
      categoryId: _categoryId,
      page: page,
    );
    try {
      final response = await _repository.fetchBooks(
        categoryId: _categoryId,
        page: page,
      );
      if (!_isCurrent(generation)) return (books: null, error: null);
      final data = response.data;
      if (response.success && data != null) {
        return (books: data, error: null);
      }
      final error = response.error ?? 'Failed to load category';
      if (_repository.isChallengeError(response.error)) {
        return _loadPageViaSolver(
          url,
          generation: generation,
          originalError: error,
        );
      }
      return (books: null, error: error);
    } catch (e) {
      if (!_isCurrent(generation)) return (books: null, error: null);
      return (books: null, error: e.toString());
    }
  }

  Future<({List<Book>? books, String? error})> _loadPageViaSolver(
    String url, {
    required int generation,
    required String originalError,
  }) async {
    final user = ref.read(authProvider).user;
    final html = await _repository.fetchViaSolver(
      url,
      userId: user?.id,
      userKey: user?.remixUserkey,
    );
    if (!_isCurrent(generation)) return (books: null, error: null);
    if (html == null) return (books: null, error: originalError);
    final books = _repository.parseBooks(
      html,
      baseUrl: Uri.parse(url).origin,
    );
    if (books == null) return (books: null, error: originalError);
    return (books: books, error: null);
  }

  void _merge(List<Book> books) {
    for (final book in books) {
      if (_bookIds.add(book.id)) _books.add(book);
    }
  }
}

final categoryBooksControllerProvider = NotifierProvider.autoDispose
    .family<CategoryBooksController, CategoryBooksState, CategoryBooksArgs>(
      CategoryBooksController.new,
    );
