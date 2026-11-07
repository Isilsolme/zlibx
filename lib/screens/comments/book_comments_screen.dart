import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/zlibrary_provider.dart';
import '../../routes/app_routes.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/gradient_app_bar.dart';
import '../../widgets/loading_widget.dart';

/// Arguments for BookCommentsScreen
class BookCommentsArgs {
  final int bookId;
  final String bookTitle;

  const BookCommentsArgs({
    required this.bookId,
    required this.bookTitle,
  });
}

/// Book comments — view, post, reply and like.
///
/// Loads the site's own `papi/` comments endpoint (50 per page,
/// 0-based) until a short page arrives, then shows the newest thread
/// first: the endpoint has no sort parameter, so every page is pulled
/// on open, grouped into threads, and reversed; scrolling reveals more
/// from the loaded list locally. Replies (`parent_id` set) are
/// indented. Posting and liking use the same `papi/` API the site's
/// own frontend uses (captured 2026-11-06). Requires a logged-in
/// session: logged-out users get a login prompt instead of a request.
class BookCommentsScreen extends ConsumerStatefulWidget {
  const BookCommentsScreen({super.key});

  @override
  ConsumerState<BookCommentsScreen> createState() =>
      _BookCommentsScreenState();
}

class _BookCommentsScreenState extends ConsumerState<BookCommentsScreen> {
  static const int _pageSize = 50;

  /// Safety cap on pages fetched in one open (20 pages = 1000
  /// comments): beyond that the oldest comments simply stay unfetched.
  static const int _maxFetchPages = 20;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _composerController = TextEditingController();
  final FocusNode _composerFocus = FocusNode();
  final List<BookComment> _comments = [];
  final Set<int> _likingIds = {};
  final Map<int, int> _replyCounts = {};
  int _visibleCount = _pageSize;
  bool _hasMore = true;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  bool _disabled = false;
  bool _loggedIn = true;
  BookComment? _replyTo;
  bool _isPosting = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFirst());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _composerController.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _isLoading || _hasError) return;
    if (_scrollController.position.extentAfter < 300) {
      // Local pagination: the whole list is already loaded, so
      // scrolling just reveals more of it.
      setState(() {
        _visibleCount += _pageSize;
        if (_visibleCount >= _comments.length) {
          _visibleCount = _comments.length;
          _hasMore = false;
        }
      });
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _submitComment() async {
    final text = _composerController.text.trim();
    if (text.isEmpty || _isPosting) return;
    // The site rejects very short comments server-side; catch the
    // obvious cases up front instead of a round trip. (4-char posts go
    // through; the exact server minimum is unknown, so only 1–2 chars
    // are blocked here — anything longer still gets the server's say.)
    if (text.length < 3) {
      _showSnack(AppLocalizations.of(context).get('comment_too_short'));
      return;
    }
    final args = ModalRoute.of(context)!.settings.arguments as BookCommentsArgs;
    final api = ref.read(zlibraryApiProvider);
    final replyTo = _replyTo;
    setState(() => _isPosting = true);
    try {
      final response = await api.postBookComment(
        args.bookId.toString(),
        text: text,
        parentId: replyTo?.id.toString(),
      );
      if (!mounted) return;
      if (response.success && response.data != null) {
        final posted = response.data!;
        setState(() {
          if (replyTo == null) {
            // New top-level comments sort to the top of the site's list.
            _comments.insert(0, posted);
          } else {
            final parentIndex =
                _comments.indexWhere((c) => c.id == replyTo.id);
            if (parentIndex >= 0) {
              _comments.insert(parentIndex + 1, posted);
              _replyCounts[replyTo.id] =
                  (_replyCounts[replyTo.id] ?? 0) + 1;
            } else {
              _comments.insert(0, posted);
            }
          }
          if (_comments.length > _visibleCount) _hasMore = true;
          _composerController.clear();
          _replyTo = null;
          _isPosting = false;
        });
        _composerFocus.unfocus();
      } else {
        setState(() => _isPosting = false);
        _showSnack(
          '${AppLocalizations.of(context).get('comment_failed')}: '
          '${response.error ?? ''}'.trim(),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPosting = false);
      _showSnack(
        '${AppLocalizations.of(context).get('comment_failed')}: $e',
      );
    }
  }

  Future<void> _toggleLike(BookComment comment) async {
    if (_likingIds.contains(comment.id)) return;
    final target = !comment.isLiked;
    final index = _comments.indexWhere((c) => c.id == comment.id);
    if (index < 0) return;
    // Optimistic toggle; the server's numbers win when it answers.
    setState(() {
      _likingIds.add(comment.id);
      _comments[index] = comment.copyWith(
        isLiked: target,
        likeCount: (comment.likeCount + (target ? 1 : -1)).clamp(0, 1 << 30),
      );
    });
    final api = ref.read(zlibraryApiProvider);
    try {
      final response = await api.likeBookComment(comment.id, like: target);
      if (!mounted) return;
      setState(() {
        _likingIds.remove(comment.id);
        final i = _comments.indexWhere((c) => c.id == comment.id);
        if (i < 0) return;
        if (response.success && response.data != null) {
          final result = response.data!;
          _comments[i] = _comments[i].copyWith(
            isLiked: result.liked,
            likeCount: result.count,
          );
        } else {
          // Revert; the server did not take it.
          _comments[i] = comment;
          _showSnack(AppLocalizations.of(context).get('like_failed'));
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _likingIds.remove(comment.id);
        final i = _comments.indexWhere((c) => c.id == comment.id);
        if (i >= 0) _comments[i] = comment;
      });
      _showSnack(AppLocalizations.of(context).get('like_failed'));
    }
  }

  Future<void> _loadFirst() async {
    if (ref.read(authProvider).user == null) {
      setState(() {
        _loggedIn = false;
        _isLoading = false;
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _hasError = false;
      _comments.clear();
      _replyCounts.clear();
      _visibleCount = _pageSize;
      _hasMore = true;
      _disabled = false;
    });
    await _loadAll();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  /// Fetch every page (oldest first, until a short page) and show the
  /// newest thread first. The endpoint has no sort parameter and no
  /// total, so the whole list is pulled on open and paged locally
  /// afterwards; a later page failing just stops the fetch and shows
  /// what arrived so far.
  Future<void> _loadAll() async {
    final args = ModalRoute.of(context)!.settings.arguments as BookCommentsArgs;
    final api = ref.read(zlibraryApiProvider);
    final collected = <BookComment>[];
    var disabled = false;
    var error = '';
    for (var page = 0; page < _maxFetchPages; page++) {
      try {
        final response = await api.getBookComments(
          args.bookId.toString(),
          page: page,
          limit: _pageSize,
        );
        if (!mounted) return;
        if (!response.success || response.data == null) {
          if (page == 0) {
            error = response.error ?? 'Failed to load comments';
          }
          break;
        }
        final data = response.data!;
        if (data.disabled) {
          disabled = true;
          break;
        }
        collected.addAll(data.comments);
        if (data.comments.length < _pageSize) break;
      } catch (e) {
        if (page == 0) error = e.toString();
        break;
      }
    }
    if (!mounted) return;
    setState(() {
      if (disabled) {
        _disabled = true;
        _hasMore = false;
      } else if (error.isNotEmpty && collected.isEmpty) {
        _hasError = true;
        _errorMessage = error;
      } else {
        _comments
          ..clear()
          ..addAll(orderCommentsNewestFirst(collected));
        _replyCounts.clear();
        for (final comment in _comments) {
          final parentId = comment.parentId;
          if (parentId != null) {
            _replyCounts[parentId] = (_replyCounts[parentId] ?? 0) + 1;
          }
        }
        _visibleCount = _pageSize;
        _hasMore = _comments.length > _visibleCount;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)!.settings.arguments as BookCommentsArgs;
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: GradientAppBar(title: l10n.get('comments')),
      body: Column(
        children: [
          // Book context header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(Icons.book_outlined, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    args.bookTitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Results
          Expanded(
            child: _isLoading
                ? LoadingWidget(message: l10n.get('loading'))
                : !_loggedIn
                    ? EmptyState(
                        icon: Icons.login_rounded,
                        title: l10n.get('login_to_view_comments'),
                        action: FilledButton(
                          onPressed: () => Navigator.of(
                            context,
                          ).pushNamed(AppRoutes.login),
                          child: Text(l10n.get('login')),
                        ),
                      )
                    : _hasError
                        ? EmptyState(
                            icon: Icons.error_outline,
                            title: l10n.get('error'),
                            message: _errorMessage,
                            action: FilledButton(
                              onPressed: _loadFirst,
                              child: Text(l10n.get('retry')),
                            ),
                          )
                        : _disabled
                            ? EmptyState(
                                icon: Icons.comments_disabled_outlined,
                                title: l10n.get('comments_disabled'),
                              )
                            : _comments.isEmpty
                                ? EmptyState(
                                    icon: Icons.comment_outlined,
                                    title: l10n.get('no_comments'),
                                  )
                                : RefreshIndicator(
                                    onRefresh: _loadFirst,
                                    child: ListView.separated(
                                      controller: _scrollController,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      itemCount: _visibleCount <
                                              _comments.length
                                          ? _visibleCount
                                          : _comments.length,
                                      separatorBuilder: (context, index) =>
                                          const Divider(
                                            height: 1,
                                            indent: 68,
                                          ),
                                      itemBuilder: (context, index) {
                                        final comment = _comments[index];
                                        return _CommentRow(
                                          comment: comment,
                                          replyCount:
                                              _replyCounts[comment.id] ?? 0,
                                          likePending: _likingIds.contains(
                                            comment.id,
                                          ),
                                          onLike: () => _toggleLike(comment),
                                          onReply: () {
                                            setState(
                                              () => _replyTo = comment,
                                            );
                                            _composerFocus.requestFocus();
                                          },
                                        );
                                      },
                                    ),
                                  ),
          ),

          // Composer (hidden while logged out or when comments are closed)
          if (_loggedIn && !_disabled && !_isLoading)
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              padding: EdgeInsets.fromLTRB(
                12,
                8,
                12,
                8 + MediaQuery.of(context).padding.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_replyTo != null)
                    Row(
                      children: [
                        Icon(
                          Icons.reply_rounded,
                          size: 16,
                          color: cs.primary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${l10n.get('reply_to')} ${_replyTo!.userName}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: cs.primary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () =>
                              setState(() => _replyTo = null),
                          tooltip: l10n.get('cancel'),
                        ),
                      ],
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _composerController,
                          focusNode: _composerFocus,
                          decoration: InputDecoration(
                            hintText: _replyTo == null
                                ? l10n.get('write_comment')
                                : '${l10n.get('reply_to')} ${_replyTo!.userName}',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _submitComment(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ListenableBuilder(
                        listenable: _composerController,
                        builder: (context, _) {
                          final canSend =
                              _composerController.text.trim().isNotEmpty &&
                              !_isPosting;
                          return IconButton.filled(
                            onPressed: canSend ? _submitComment : null,
                            icon: _isPosting
                                ? const LoadingWidget.inline(
                                    color: Colors.white,
                                  )
                                : const Icon(
                                    Icons.send_rounded,
                                    size: 20,
                                  ),
                            tooltip: l10n.get('send_comment'),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  final BookComment comment;
  final int replyCount;
  final bool likePending;
  final VoidCallback onLike;
  final VoidCallback onReply;

  const _CommentRow({
    required this.comment,
    required this.replyCount,
    required this.likePending,
    required this.onLike,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final date = comment.dateRelative.isNotEmpty
        ? comment.dateRelative
        : comment.date;
    // Replies to another comment are indented.
    final indent = comment.parentId != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(indent ? 56 : 16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: cs.primaryContainer,
            backgroundImage: comment.userAvatar.isNotEmpty
                ? NetworkImage(comment.userAvatar)
                : null,
            child: comment.userAvatar.isEmpty
                ? Icon(
                    Icons.person_rounded,
                    color: cs.onPrimaryContainer,
                    size: 22,
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  comment.userName,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  comment.text,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      date,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: onReply,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 16,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              replyCount.toString(),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    InkWell(
                      onTap: likePending ? null : onLike,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              comment.isLiked
                                  ? Icons.thumb_up_rounded
                                  : Icons.thumb_up_outlined,
                              size: 16,
                              color: comment.isLiked
                                  ? cs.primary
                                  : cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              comment.likeCount.toString(),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: comment.isLiked
                                        ? cs.primary
                                        : cs.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
