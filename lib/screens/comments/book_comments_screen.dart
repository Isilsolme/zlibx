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

/// Book comments, view-only.
///
/// Loads the site's own `papi/` comments endpoint page by page (50 per
/// page, 0-based) until a short page arrives. Replies (`parent_id` set)
/// are indented. Requires a logged-in session: logged-out users get a
/// login prompt instead of a request.
class BookCommentsScreen extends ConsumerStatefulWidget {
  const BookCommentsScreen({super.key});

  @override
  ConsumerState<BookCommentsScreen> createState() =>
      _BookCommentsScreenState();
}

class _BookCommentsScreenState extends ConsumerState<BookCommentsScreen> {
  static const int _pageSize = 50;

  final ScrollController _scrollController = ScrollController();
  final List<BookComment> _comments = [];
  int _nextPage = 0;
  bool _hasMore = true;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasError = false;
  String _errorMessage = '';
  bool _disabled = false;
  bool _loggedIn = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFirst());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _isLoadingMore || _isLoading || _hasError) return;
    if (_scrollController.position.extentAfter < 300) {
      _loadPage(_nextPage);
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
      _nextPage = 0;
      _hasMore = true;
      _disabled = false;
    });
    await _loadPage(0);
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPage(int page) async {
    final args = ModalRoute.of(context)!.settings.arguments as BookCommentsArgs;
    final api = ref.read(zlibraryApiProvider);
    if (page > 0) {
      setState(() => _isLoadingMore = true);
    }
    try {
      final response = await api.getBookComments(
        args.bookId.toString(),
        page: page,
        limit: _pageSize,
      );
      if (!mounted) return;
      if (response.success && response.data != null) {
        final data = response.data!;
        setState(() {
          if (data.disabled) {
            _disabled = true;
            _hasMore = false;
          } else {
            _comments.addAll(data.comments);
            _hasMore = data.comments.length >= _pageSize;
            _nextPage = page + 1;
          }
          _isLoadingMore = false;
        });
      } else {
        setState(() {
          _isLoadingMore = false;
          if (page == 0) {
            _hasError = true;
            _errorMessage = response.error ?? 'Failed to load comments';
          } else {
            _hasMore = false;
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
        if (page == 0) {
          _hasError = true;
          _errorMessage = e.toString();
        } else {
          _hasMore = false;
        }
      });
    }
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
                                      itemCount:
                                          _comments.length +
                                          (_isLoadingMore ? 1 : 0),
                                      separatorBuilder: (context, index) =>
                                          const Divider(
                                            height: 1,
                                            indent: 68,
                                          ),
                                      itemBuilder: (context, index) {
                                        if (index >= _comments.length) {
                                          return const Padding(
                                            padding: EdgeInsets.all(16),
                                            child: Center(
                                              child:
                                                  CircularProgressIndicator(),
                                            ),
                                          );
                                        }
                                        return _CommentRow(
                                          comment: _comments[index],
                                        );
                                      },
                                    ),
                                  ),
          ),
        ],
      ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  final BookComment comment;

  const _CommentRow({required this.comment});

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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        comment.userName,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      date,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  comment.text,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
