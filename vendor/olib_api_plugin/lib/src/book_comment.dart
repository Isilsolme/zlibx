/// One Z-Library book comment, from the site's own `papi/` JSON API
/// (`GET /papi/comments/book/{bookId}/{page}?limit={limit}`).
///
/// This endpoint is NOT part of eapi: it is the website frontend's API,
/// confirmed by a packet capture on 2026-11-06 (book page on
/// zh.z-library.sk). Auth is the same `remix_userid` / `remix_userkey`
/// session cookies the eapi calls already send, so it needs a logged-in
/// session. View-only: posting / liking / deleting exist in the site's
/// JS (`papi/comments/add`, `/like/...`, `/delete/...`) but are not
/// wired here.
class BookComment {
  final int id;

  /// Null for top-level comments; the id of the comment this replies to.
  final int? parentId;
  final int userId;
  final String text;

  /// Server timestamp, e.g. "2022-05-20 18:42:37".
  final String date;
  final String userName;

  /// Absolute avatar URL (resolved from the relative `cover`/`avatar`
  /// path against the mirror), or '' when the user has none.
  final String userAvatar;

  /// Relative date as the site renders it (e.g. "4年前"), or ''.
  final String dateRelative;
  final bool isCurrentUser;

  const BookComment({
    required this.id,
    required this.parentId,
    required this.userId,
    required this.text,
    required this.date,
    required this.userName,
    required this.userAvatar,
    required this.dateRelative,
    required this.isCurrentUser,
  });

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
