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
import 'controllers/book_comments_controller.dart';
import 'widgets/book_context_header.dart';
import 'widgets/comment_composer.dart';
import 'widgets/comment_list.dart';

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
/// 逻辑在 [BookCommentsController]；这里只负责接 provider、组装
/// 上下文条 / 状态视图 / 列表 / 输入区，并发起导航与聚焦。
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

  bool get _signedIn => ref.read(authProvider).user != null;

  Future<void> _reload() => _c.loadFirst(signedIn: _signedIn);

  Future<void> _submit() async {
    final text = _composerController.text.trim();
    if (text.isEmpty || _c.isPosting) return;
    // 服务端会拒绝过短评论；明显的 1–2 字符直接在前端拦掉。
    if (text.length < 3) {
      _showSnack(AppLocalizations.of(context).get('comment_too_short'));
      return;
    }
    final wasReply = _c.replyTo != null;
    final posted = await _c.submit(text);
    if (!mounted) return;
    if (posted) {
      _composerController.clear();
      _composerFocus.unfocus();
      // 新顶层评论插在最前，滚回顶部让用户立刻看到自己的评论；
      // 回复则原地不动（父评论就在视口附近）。
      if (!wasReply && _scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  void _openProfile(BookComment comment) {
    Navigator.of(context).pushNamed(
      AppRoutes.userProfile,
      arguments: UserProfileArgs(
        userId: comment.userId,
        userName: comment.userName,
        userAvatar: comment.userAvatar,
        userHash: comment.userHash,
      ),
    );
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
              BookContextHeader(
                title: args.bookTitle,
                commentCount:
                    c.loggedIn && !c.disabled && !c.hasError && !c.isLoading
                        ? c.comments.length
                        : null,
              ),
              Expanded(child: _buildBody(c, l10n)),
              if (c.loggedIn && !c.disabled && !c.isLoading)
                CommentComposer(
                  controller: _composerController,
                  focusNode: _composerFocus,
                  hintText: l10n.get('write_comment'),
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

  /// 状态视图分发：加载 / 未登录 / 出错 / 关闭 / 空 / 列表。
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
          onPressed: _reload,
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
    return CommentList(
      controller: c,
      scrollController: _scrollController,
      onRefresh: _reload,
      visibleCount: c.visibleCount,
      noMoreText: l10n.get('no_more_comments'),
      onReply: (comment) {
        _c.beginReply(comment);
        _composerFocus.requestFocus();
      },
      onAvatarTap: _openProfile,
      onLike: _c.toggleLike,
    );
  }
}
