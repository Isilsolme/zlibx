import 'package:flutter_test/flutter_test.dart';
import 'package:zlibx/screens/account/my_comments_screen.dart';

void main() {
  test('newest first reverses the server order', () {
    final comments = [
      const MyComment(
        id: 1,
        bookId: 10,
        bookTitle: 'a',
        text: 'first',
        date: '3 days ago',
        userId: 1,
      ),
      const MyComment(
        id: 2,
        bookId: 11,
        bookTitle: 'b',
        text: 'second',
        date: '2 days ago',
        userId: 1,
      ),
      const MyComment(
        id: 3,
        bookId: 12,
        bookTitle: 'c',
        text: 'third',
        date: '1 day ago',
        userId: 1,
      ),
    ];
    final ordered = orderMyCommentsNewestFirst(comments);
    expect(ordered.map((c) => c.id).toList(), [3, 2, 1]);
    // The input list is untouched.
    expect(comments.map((c) => c.id).toList(), [1, 2, 3]);
  });

  test('empty and single-comment lists stay as-is', () {
    expect(orderMyCommentsNewestFirst(const []), isEmpty);
    const one = [
      MyComment(
        id: 7,
        bookId: 10,
        bookTitle: 'a',
        text: 'x',
        date: '',
        userId: 1,
      ),
    ];
    expect(
      orderMyCommentsNewestFirst(one).map((c) => c.id).toList(),
      [7],
    );
  });
}
