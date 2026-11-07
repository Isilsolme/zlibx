import 'package:flutter_test/flutter_test.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

const _baseUrl = 'https://zh.z-library.sk';

void main() {
  group('BookComment.fromJson', () {
    test('per-book read: top-level comment, cover avatar resolved', () {
      final comment = BookComment.fromJson(const {
        'id': 101,
        'object': 'book',
        'object_id': 6134915,
        'parent_id': null,
        'user_id': 7,
        'text': '很好',
        'date': '2022-05-20 18:42:37',
        'user': {
          'name': '徕',
          'cover': '/img/profile/cover-0.png',
          'avatar': '',
          'hash': 'abc',
          'isPremium': false,
          'isCurrentUser': false,
          'dateRelative': '4年前',
        },
      }, baseUrl: _baseUrl);
      expect(comment.id, 101);
      expect(comment.parentId, isNull);
      expect(comment.userId, 7);
      expect(comment.text, '很好');
      expect(comment.userName, '徕');
      expect(comment.userHash, 'abc');
      expect(comment.userAvatar, '$_baseUrl/img/profile/cover-0.png');
      expect(comment.dateRelative, '4年前');
      expect(comment.isCurrentUser, isFalse);
      expect(comment.likeCount, 0);
      expect(comment.isLiked, isFalse);
    });

    test('reply: string parent_id and user_id are coerced', () {
      final comment = BookComment.fromJson(const {
        'id': '102',
        'parent_id': '101',
        'user_id': '8',
        'text': '同意',
        'date': '2022-05-21 10:00:00',
        'user': {'name': '路人', 'avatar': 'https://cdn.example.com/a.jpg'},
      }, baseUrl: _baseUrl);
      expect(comment.id, 102);
      expect(comment.parentId, 101);
      expect(comment.userId, 8);
      expect(comment.userAvatar, 'https://cdn.example.com/a.jpg');
    });

    test('missing user map degrades to empty name and avatar', () {
      final comment = BookComment.fromJson(const {
        'id': 103,
        'text': 'x',
      });
      expect(comment.userName, '');
      expect(comment.userAvatar, '');
      expect(comment.parentId, isNull);
    });
  });

  group('orderCommentsNewestFirst', () {
    BookComment comment(int id, {int? parentId}) => BookComment(
          id: id,
          parentId: parentId,
          userId: 1,
          text: 'c$id',
          date: '2022-01-01 00:00:00',
          userName: 'u',
          userAvatar: '',
          dateRelative: '',
          isCurrentUser: false,
        );

    List<int> ids(List<BookComment> comments) =>
        comments.map((c) => c.id).toList();

    test('threads reverse, replies stay after their parent', () {
      expect(
        ids(orderCommentsNewestFirst([
          comment(1),
          comment(11, parentId: 1),
          comment(12, parentId: 1),
          comment(2),
          comment(21, parentId: 2),
          comment(3),
        ])),
        [3, 2, 21, 1, 11, 12],
      );
    });

    test('orphan reply keeps its server position', () {
      expect(
        ids(orderCommentsNewestFirst([
          comment(1),
          comment(99, parentId: 999),
          comment(2),
        ])),
        [2, 99, 1],
      );
    });

    test('reply before its parent still attaches', () {
      expect(
        ids(orderCommentsNewestFirst([
          comment(11, parentId: 1),
          comment(1),
        ])),
        [1, 11],
      );
    });

    test('nested reply joins the ancestor thread', () {
      expect(
        ids(orderCommentsNewestFirst([
          comment(1),
          comment(2, parentId: 1),
          comment(3, parentId: 2),
        ])),
        [1, 2, 3],
      );
    });

    test('empty and single-comment lists pass through', () {
      expect(orderCommentsNewestFirst(const []), isEmpty);
      expect(ids(orderCommentsNewestFirst([comment(1)])), [1]);
    });
  });

  group('commentTitlesOf', () {
    test('map form keyed by book id, string and map values', () {
      final titles = commentTitlesOf(const {
        'commentsTitles': {
          'book': {
            '6134915': '三体',
            '5288001': {'title': '底层逻辑'},
            'bad': 'skipped',
            '1': '',
          },
        },
      });
      expect(titles, {6134915: '三体', 5288001: '底层逻辑'});
    });

    test('list form with book_id/title pairs', () {
      final titles = commentTitlesOf(const {
        'commentsTitles': {
          'book': [
            {'book_id': 5, 'title': 'A'},
            {'id': '6', 'name': 'B'},
            {'title': 'no id'},
          ],
        },
      });
      expect(titles, {5: 'A', 6: 'B'});
    });

    test('missing or unparseable titles give an empty map', () {
      expect(commentTitlesOf(const {}), isEmpty);
      expect(commentTitlesOf(const {'commentsTitles': 'nope'}), isEmpty);
      expect(commentTitlesOf(const {'commentsTitles': {'book': 42}}), isEmpty);
    });
  });

  group('commentReactionsOf', () {
    test('list form: counts plus liked flags', () {
      final reactions = commentReactionsOf(const {
        'reactionsInfo': {
          'reactions': [
            {'item_id': 101, 'count': 3},
            {'item_id': 102, 'count': 0},
          ],
          'isLiked': [
            {'item_id': 101, 'status': 1},
          ],
        },
      });
      expect(reactions[101]!.count, 3);
      expect(reactions[101]!.liked, isTrue);
      expect(reactions[102]!.count, 0);
      expect(reactions[102]!.liked, isFalse);
    });

    test('map form: counts and liked flags keyed by id', () {
      final reactions = commentReactionsOf(const {
        'reactionsInfo': {
          'reactions': {'101': 2},
          'isLiked': {'101': 1, '102': 0},
        },
      });
      expect(reactions[101]!.count, 2);
      expect(reactions[101]!.liked, isTrue);
      expect(reactions.containsKey(102), isFalse);
    });

    test('unparseable reactions give an empty map', () {
      expect(commentReactionsOf(const {}), isEmpty);
      expect(
        commentReactionsOf(const {'reactionsInfo': 'nope'}),
        isEmpty,
      );
    });
  });

  group('CommentLikeResult.fromLikeJson', () {
    test('picks the entry for the liked comment id', () {
      final result = CommentLikeResult.fromLikeJson(const {
        'likes': [
          {'item_id': 101, 'status': 1, 'count': 5},
        ],
        'isLiked': [
          {'item_id': 101, 'status': 1},
        ],
      }, 101);
      expect(result!.count, 5);
      expect(result.liked, isTrue);
    });

    test('absent comment id returns null', () {
      expect(
        CommentLikeResult.fromLikeJson(const {
          'likes': [
            {'item_id': 101, 'status': 1, 'count': 5},
          ],
          'isLiked': [],
        }, 999),
        isNull,
      );
      expect(CommentLikeResult.fromLikeJson(const {}, 101), isNull);
    });
  });

  group('Book.fromJson', () {
    test('derives the hash from href, joins list authors, formats size', () {
      final book = Book.fromJson(const {
        'id': '6134915',
        'title': '三体',
        'href': '/book/abc123def456/san-ti.html',
        'author': ['刘慈欣'],
        'publisher': '重庆出版社',
        'year': '2006',
        'language': 'Chinese',
        'extension': 'epub',
        'filesize': 14000000,
        'qualityScore': '4.5',
      });
      expect(book.id, 6134915);
      expect(book.hash, 'abc123def456');
      expect(book.author, '刘慈欣');
      expect(book.year, 2006);
      expect(book.filesizeString, '13.35 MB');
      expect(book.interestScore, '4.5');
    });

    test('explicit hash and filesizeString win over derivation', () {
      final book = Book.fromJson(const {
        'id': 1,
        'title': 'T',
        'hash': 'explicit',
        'hashId': 'ignored',
        'filesizeString': '2.06 MB',
        'filesize': 999,
      });
      expect(book.hash, 'explicit');
      expect(book.filesizeString, '2.06 MB');
    });

    test('byte sizes format as B and KB', () {
      expect(Book.fromJson(const {'id': 1, 'title': 'T', 'filesize': 512})
          .filesizeString, '512 B');
      expect(Book.fromJson(const {'id': 1, 'title': 'T', 'filesize': 2048})
          .filesizeString, '2.0 KB');
    });

    test('categories parse from string and list forms', () {
      expect(
        Book.fromJson(const {
          'id': 1,
          'title': 'T',
          'categories': 'Fiction - Horror',
        }).categories,
        'Fiction - Horror',
      );
      expect(
        Book.fromJson(const {
          'id': 1,
          'title': 'T',
          'categories': ['Fiction', 'Horror'],
        }).categories,
        'Fiction, Horror',
      );
      expect(
        Book.fromJson(const {'id': 1, 'title': 'T'}).categories,
        isNull,
      );
    });

    test('minimal json degrades to defaults', () {
      final book = Book.fromJson(const {'id': 2, 'title': 'T'});
      expect(book.hash, isNull);
      expect(book.author, isNull);
      expect(book.cover, isNull);
      expect(book.description, isNull);
      expect(book.filesizeString, isNull);
    });
  });
}
