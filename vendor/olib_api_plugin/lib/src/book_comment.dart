/// One Z-Library book comment, from the site's own `papi/` JSON API
/// (`GET /papi/comments/book/{bookId}/{page}?limit={limit}`).
///
/// This endpoint is NOT part of eapi: it is the website frontend's API,
/// confirmed by a packet capture on 2026-11-06 (book page on
/// zh.z-library.sk). Auth is the same `remix_userid` / `remix_userkey`
/// session cookies the eapi calls already send, so it needs a logged-in
/// session. Posting, replying and liking are wired too (same capture
/// series): `POST /papi/comments/add` and
/// `POST /papi/comments/like/{commentId}/{1|0}`.
class BookComment {
  final int id;

  /// Null for top-level comments; the id of the comment this replies to.
  final int? parentId;
  final int userId;
  final String text;

  /// Server timestamp, e.g. "2022-05-20 18:42:37".
  final String date;
  final String userName;

  /// The profile hash from the comment's `user.hash` — the second
  /// segment of the profile URL (`/profile/{userId}/{hash}`). This is
  /// NOT the avatar filename suffix: the avatar URL carries a
  /// different hash (own user: avatar `.../35899435_3cc9e9.jpg` vs
  /// profile hash `5a9053`), so never derive it from the avatar.
  /// '' when the server did not say.
  final String userHash;

  /// Absolute avatar URL (resolved from the relative `cover`/`avatar`
  /// path against the mirror), or '' when the user has none.
  final String userAvatar;

  /// Relative date as the site renders it (e.g. "4年前"), or ''.
  final String dateRelative;
  final bool isCurrentUser;

  /// Number of likes, from the page's `reactionsInfo` (best effort) or
  /// from a like response. 0 when the server did not say.
  final int likeCount;

  /// Whether the current user likes this comment.
  final bool isLiked;

  const BookComment({
    required this.id,
    required this.parentId,
    required this.userId,
    required this.text,
    required this.date,
    required this.userName,
    this.userHash = '',
    required this.userAvatar,
    required this.dateRelative,
    required this.isCurrentUser,
    this.likeCount = 0,
    this.isLiked = false,
  });

  BookComment copyWith({int? likeCount, bool? isLiked}) {
    return BookComment(
      id: id,
      parentId: parentId,
      userId: userId,
      text: text,
      date: date,
      userName: userName,
      userHash: userHash,
      userAvatar: userAvatar,
      dateRelative: dateRelative,
      isCurrentUser: isCurrentUser,
      likeCount: likeCount ?? this.likeCount,
      isLiked: isLiked ?? this.isLiked,
    );
  }

  factory BookComment.fromJson(
    Map<String, dynamic> json, {
    String? baseUrl,
  }) {
    final user = json['user'] is Map<String, dynamic>
        ? json['user'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final avatar = _asString(user['avatar']) ?? '';
    final cover = _asString(user['cover']) ?? '';
    final rawAvatar = avatar.isNotEmpty ? avatar : cover;
    final resolvedAvatar = rawAvatar.isEmpty
        ? ''
        : rawAvatar.startsWith('http')
            ? rawAvatar
            : (baseUrl != null && rawAvatar.startsWith('/')
                ? '$baseUrl$rawAvatar'
                : rawAvatar);
    return BookComment(
      id: _asInt(json['id']) ?? 0,
      parentId: _asInt(json['parent_id']),
      userId: _asInt(json['user_id']) ?? 0,
      text: _asString(json['text']) ?? '',
      date: _asString(json['date']) ?? '',
      userName: _asString(user['name']) ?? '',
      userHash: _asString(user['hash']) ?? '',
      userAvatar: resolvedAvatar,
      dateRelative: _asString(user['dateRelative']) ?? '',
      isCurrentUser: user['isCurrentUser'] == true,
    );
  }
}

/// One page of book comments.
///
/// The response carries no total/pages fields, so callers page until a
/// short page arrives. [disabled] mirrors the `commentsDisabled` flag:
/// the book takes no comments at all.
class BookCommentsPage {
  final List<BookComment> comments;
  final bool disabled;

  const BookCommentsPage({
    required this.comments,
    this.disabled = false,
  });
}

/// Reorder a server-order comment list (oldest first, replies directly
/// after their parent) so the newest thread comes first: group each
/// top-level comment with its replies, in server order, then reverse
/// the thread order. Replies keep their position directly after their
/// parent; a reply whose parent is missing (deleted, or not fetched)
/// becomes its own thread at its server position. The site's read
/// endpoint has no sort parameter and no total, so this is how the
/// newest-first view is built client-side.
List<BookComment> orderCommentsNewestFirst(List<BookComment> serverOrder) {
  // Threads in server order, plus the server index each thread starts
  // at (top-level comment, or first orphan reply).
  final threads = <List<BookComment>>[];
  final threadPositions = <int>[];
  // Comment id -> thread index, for every comment placed so far.
  final threadOf = <int, int>{};
  // Replies whose parent has not been placed yet, keyed by parent id.
  final pending = <int, List<BookComment>>{};
  final pendingFirstIndex = <int, int>{};

  void place(BookComment comment, int threadIndex) {
    threads[threadIndex].add(comment);
    threadOf[comment.id] = threadIndex;
    // A reply waiting on this comment joins the same thread now.
    final waiting = pending.remove(comment.id);
    if (waiting != null) {
      for (final reply in waiting) {
        place(reply, threadIndex);
      }
    }
  }

  for (var i = 0; i < serverOrder.length; i++) {
    final comment = serverOrder[i];
    final parentId = comment.parentId;
    if (parentId == null) {
      threads.add(<BookComment>[]);
      threadPositions.add(i);
      place(comment, threads.length - 1);
    } else if (threadOf.containsKey(parentId)) {
      place(comment, threadOf[parentId]!);
    } else {
      pending.putIfAbsent(parentId, () => <BookComment>[]);
      pendingFirstIndex.putIfAbsent(parentId, () => i);
      pending[parentId]!.add(comment);
    }
  }
  for (final entry in pending.entries) {
    threads.add(entry.value);
    threadPositions.add(pendingFirstIndex[entry.key]!);
  }

  final order = List<int>.generate(threads.length, (i) => i)
    ..sort((a, b) => threadPositions[b].compareTo(threadPositions[a]));
  final ordered = <BookComment>[];
  for (final index in order) {
    ordered.addAll(threads[index]);
  }
  return ordered;
}

/// One of the signed-in user's own comments, with the book it was posted
/// on, from the website's profile Comments tab:
/// `GET /papi/comments/user/{userId}/{page}?limit={limit}`.
/// Confirmed by a packet capture on 2026-11-06 (zh.z-library.sk profile
/// page). That response carries `comments` as a MAP keyed by comment id
/// (not a list, unlike the per-book read) and `commentsTitles` with the
/// book title for each comment.
class UserCommentEntry {
  final BookComment comment;
  final int bookId;
  final String bookTitle;

  const UserCommentEntry({
    required this.comment,
    required this.bookId,
    required this.bookTitle,
  });
}

/// One page of the signed-in user's own comments.
class UserCommentsPage {
  final List<UserCommentEntry> entries;

  const UserCommentsPage({required this.entries});
}

/// Best-effort book titles from a user-comments page's `commentsTitles`
/// (`{book: {<bookId>: <title-ish>}}`). The title value's exact shape is
/// not fully pinned down, so strings are taken as-is and maps are read
/// via `title`/`name`; a list form (`[{book_id/id/object_id, title}]`)
/// is accepted too. Anything unparseable is skipped.
Map<int, String> commentTitlesOf(Map<String, dynamic> pageJson) {
  final out = <int, String>{};
  final titles = pageJson['commentsTitles'];
  if (titles is! Map) return out;
  final books = titles['book'];
  if (books is List) {
    for (final entry in books) {
      if (entry is! Map) continue;
      final id = _asInt(
        entry['book_id'] ??
            entry['id'] ??
            entry['object_id'],
      );
      final title =
          _asString(entry['title']) ?? _asString(entry['name']);
      if (id != null && title != null && title.isNotEmpty) {
        out[id] = title;
      }
    }
    return out;
  }
  if (books is! Map) return out;
  for (final entry in books.entries) {
    final id = int.tryParse(entry.key.toString());
    if (id == null) continue;
    final value = entry.value;
    String? title;
    if (value is String) {
      title = value;
    } else if (value is Map) {
      title = _asString(value['title']) ?? _asString(value['name']);
    }
    if (title != null && title.isNotEmpty) out[id] = title;
  }
  return out;
}

/// The server's answer to a like/unlike: the comment's new like count
/// and whether the current user likes it now.
class CommentLikeResult {
  final int count;
  final bool liked;

  const CommentLikeResult({required this.count, required this.liked});

  /// Pick the entry for [commentId] out of a like response's `likes` /
  /// `isLiked` arrays (`[{item_id, status, count, users}]` and
  /// `[{item_id, status}]`). Returns null when the comment is absent.
  static CommentLikeResult? fromLikeJson(
    Map<String, dynamic> json,
    int commentId,
  ) {
    int? count;
    bool? liked;
    final likes = json['likes'];
    if (likes is List) {
      for (final entry in likes) {
        if (entry is! Map<String, dynamic>) continue;
        if (_asInt(entry['item_id']) != commentId) continue;
        count = _asInt(entry['count']);
      }
    }
    final isLiked = json['isLiked'];
    if (isLiked is List) {
      for (final entry in isLiked) {
        if (entry is! Map<String, dynamic>) continue;
        if (_asInt(entry['item_id']) != commentId) continue;
        liked = _asInt(entry['status']) == 1;
      }
    }
    if (count == null && liked == null) return null;
    return CommentLikeResult(count: count ?? 0, liked: liked ?? false);
  }
}

/// Best-effort per-comment like state from a comments page's
/// `reactionsInfo` (`{reactions, isLiked}`). The exact shape varies, so
/// anything unparseable is ignored and the comment keeps its defaults
/// (0 likes, not liked). Both list-of-maps and map forms are accepted.
Map<int, CommentLikeResult> commentReactionsOf(
  Map<String, dynamic> pageJson,
) {
  final info = pageJson['reactionsInfo'];
  if (info is! Map<String, dynamic>) return const {};
  final counts = <int, int>{};
  final liked = <int>{};
  final reactions = info['reactions'];
  if (reactions is List) {
    for (final entry in reactions) {
      if (entry is! Map<String, dynamic>) continue;
      final id = _asInt(entry['item_id']);
      final count = _asInt(entry['count']);
      if (id != null && count != null) counts[id] = count;
    }
  } else if (reactions is Map) {
    for (final entry in reactions.entries) {
      final id = int.tryParse(entry.key.toString());
      final value = entry.value;
      final count = value is Map
          ? _asInt(value['count'])
          : _asInt(value);
      if (id != null && count != null) counts[id] = count;
    }
  }
  final isLiked = info['isLiked'];
  if (isLiked is List) {
    for (final entry in isLiked) {
      if (entry is! Map<String, dynamic>) continue;
      final id = _asInt(entry['item_id']);
      if (id != null && _asInt(entry['status']) == 1) liked.add(id);
    }
  } else if (isLiked is Map) {
    for (final entry in isLiked.entries) {
      final id = int.tryParse(entry.key.toString());
      final value = entry.value;
      final on =
          value == 1 || value == true || value.toString() == '1';
      if (id != null && on) liked.add(id);
    }
  }
  final out = <int, CommentLikeResult>{};
  for (final id in {...counts.keys, ...liked}) {
    out[id] = CommentLikeResult(
      count: counts[id] ?? 0,
      liked: liked.contains(id),
    );
  }
  return out;
}

String? _asString(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  return v.toString();
}

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.toInt();
  return int.tryParse(v.toString());
}
