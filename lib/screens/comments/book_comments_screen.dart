import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/zlibrary_provider.dart';
import '../../routes/app_routes.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/gradient_app_bar.dart';
import '../../widgets/loading_widget.dart';
import 'controllers/book_comments_controller.dart';
import 'widgets/comment_card.dart';
import 'widgets/comment_composer.dart';

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
/// 逻辑在 [BookCommentsController]；这里只负责接 provider 与构建 UI。
/// 需要登录会话，未登录显示登录入口。详见 controller 文档。
class BookCommentsScreen extends ConsumerStatefulWidget {
  const BookCommentsScreen({super.key});

  @override
  ConsumerState<BookCommentsScreen> createState() =>
      _BookCommentsScreenState();
}

class _BookCommentsScreenState extends ConsumerState<BookCommentsScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _composerController = TextEditingController();
  final FocusNode _composerFocus = FocusNode();

  BookCommentsController? _controller;

  BookCommentsController get _c => _controller!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final args =
        ModalRoute.of(context)!.settings.arguments as BookCommentsArgs;
    _controller = BookCommentsController(
      bookId: args.bookId,
      api: ref.read(zlibraryApiProvider),
      tr: (key) => AppLocalizations.of(context).get(key),
      onNotice: _showSnack,
    );
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _c.loadFirst(
        signedIn: ref.read(authProvider).user != null,
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _scrollController.dispose();
    _composerController.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 300) _c.showMore();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    final text = _composerController.text.trim();
    if (text.isEmpty || _c.isPosting) return;
    // 服务端会拒绝过短评论；明显的 1–2 字符直接在前端拦掉。
    if (text.length < 3) {
      _showSnack(AppLocalizations.of(context).get('comment_too_short'));
      return;
    }
    final posted = await _c.submit(text);
    if (!mounted) return;
    if (posted) {
      _composerController.clear();
      _composerFocus.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)!.settings.arguments as BookCommentsArgs;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: GradientAppBar(title: l10n.get('comments')),
      body: ListenableBuilder(
        listenable: _c,
        builder: (context, _) {
          final c = _c;
          return Column(
            children: [
              _BookContextHeader(title: args.bookTitle),
              Expanded(child: _buildBody(c, l10n)),
              if (c.loggedIn && !c.disabled && !c.isLoading)
                CommentComposer(
                  controller: _composerController,
                  focusNode: _composerFocus,
                  hintText: c.replyTo == null
                      ? l10n.get('write_comment')
                      : '${l10n.get('reply_to')} ${c.replyTo!.userName}',
                  replyBannerText: c.replyTo == null
                      ? null
                      : '${l10n.get('reply_to')} ${c.replyTo!.userName}',
                  cancelTooltip: l10n.get('cancel'),
                  sendTooltip: l10n.get('send_comment'),
                  isPosting: c.isPosting,
                  onCancelReply: c.cancelReply,
                  onSubmit: _submit,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBody(BookCommentsController c, AppLocalizations l10n) {
    if (c.isLoading) return LoadingWidget(message: l10n.get('loading'));
    if (!c.loggedIn) {
      return EmptyState(
        icon: Icons.login_rounded,
        title: l10n.get('login_to_view_comments'),
        action: FilledButton(
          onPressed: () => Navigator.of(context).pushNamed(AppRoutes.login),
          child: Text(l10n.get('login')),
        ),
      );
    }
    if (c.hasError) {
      return EmptyState(
        icon: Icons.error_outline,
        title: l10n.get('error'),
        message: c.errorMessage,
        action: FilledButton(
          onPressed: () => _c.loadFirst(
            signedIn: ref.read(authProvider).user != null,
          ),
          child: Text(l10n.get('retry')),
        ),
      );
    }
    if (c.disabled) {
      return EmptyState(
        icon: Icons.comments_disabled_outlined,
        title: l10n.get('comments_disabled'),
      );
    }
    if (c.comments.isEmpty) {
      return EmptyState(
        icon: Icons.comment_outlined,
        title: l10n.get('no_comments'),
      );
    }
    return _buildList(c);
  }

  Widget _buildList(BookCommentsController c) {
    final shown =
        c.visibleCount < c.comments.length ? c.visibleCount : c.comments.length;
    return RefreshIndicator(
      onRefresh: () =>
          _c.loadFirst(signedIn: ref.read(authProvider).user != null),
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: shown + (c.hasMore ? 1 : 0),
        // 视觉上把线程分组：顶层评论之后留白，回复紧贴着父评论。
        separatorBuilder: (context, index) {
          final list = c.comments;
          if (index >= list.length) return const SizedBox.shrink();
          return SizedBox(height: list[index].parentId == null ? 14 : 2);
        },
        itemBuilder: (context, index) {
          final list = c.comments;
          if (index >= shown) {
            // 本地分页的加载尾部
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            );
          }
          final comment = list[index];
          return CommentCard(
            comment: comment,
            replyCount: c.replyCounts[comment.id] ?? 0,
            likePending: c.likingIds.contains(comment.id),
            onLike: () => _c.toggleLike(comment),
            onReply: () {
              _c.beginReply(comment);
              _composerFocus.requestFocus();
            },
            onAvatarTap: () => Navigator.of(context).pushNamed(
              AppRoutes.userProfile,
              arguments: UserProfileArgs(
                userId: comment.userId,
                userName: comment.userName,
                userAvatar: comment.userAvatar,
                userHash: comment.userHash,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 顶部书目上下文条：图标 + 书名。
class _BookContextHeader extends StatelessWidget {
  final String title;

  const _BookContextHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.book_outlined,
              size: 18,
              color: cs.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
