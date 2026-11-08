import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/zlibrary_provider.dart';
import '../../routes/app_routes.dart';
import '../../screens/book_detail/book_detail_args.dart';
import '../../screens/comments/widgets/comment_avatar.dart';
import '../../screens/comments/widgets/comment_metric_chip.dart';
import '../../services/challenge_html_cache.dart';
import '../../services/booklist_html_cache.dart';
import '../../services/wall_cookie_bridge.dart';
import '../../services/webview_challenge_solver.dart';
import '../../widgets/booklist_row.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/gradient_app_bar.dart';
import '../../widgets/loading_widget.dart';
import '../comments/book_comments_screen.dart';
import 'booklist_detail_screen.dart';
import 'comment_book_ref.dart';

/// Another user's profile page, reached by tapping an avatar in a
/// comment row. Header (avatar + name from the tapped comment),
/// then that user's booklists (from the profile document's
/// server-rendered booklists tab) and their posted comments (via
/// `getUserComments`, same endpoint order as "My Comments").
/// Their saved books are NOT shown: other users' profiles have no
/// library tab on the site, and `getUserSaved` reads the session
/// user only. The reading queue (`z-tab="plans"`) is NOT shown
/// either: its content was cut off in the capture and the app has
/// no reading-queue concept. Tapping a comment opens that book's
/// comments page; tapping its book-title row (cover thumbnail + title)
/// opens the book's detail page (the user-comments endpoint carries no
/// book hash, so it is resolved by a title search first — see
/// [_UserProfileScreenState._openBookDetail]); tapping a booklist
/// opens its detail page, with the carousel preview painting instantly.
class UserProfileScreen extends ConsumerStatefulWidget {
  const UserProfileScreen({super.key});

  @override
  ConsumerState<UserProfileScreen> createState() =>
      _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> {
  List<UserCommentEntry> _entries = [];
  List<Booklist> _booklists = [];
  bool _isLoading = true;
  bool _loggedIn = true;
  bool _booklistsLoading = false;
  String? _booklistsError;

  /// bookId → 标题搜索反查结果（hash + 封面）。评论加载后逐本后台
  /// 串行预取，每解析完一本就刷新对应书名行的封面；跳详情优先用
  /// 缓存里的 hash。
  final Map<int, CommentBookRef> _bookRefs = {};

  /// 正在解析书 hash 并准备跳详情的 bookId：书名行尾转圈，防重复点击。
  final Set<int> _openingBookIds = {};

  /// 预取上限：评论一次可拉回很多条，逐本搜索会放大请求量，只预取
  /// 前 [_kMaxBookPrefetch] 本（足够铺满几屏）；未预取到的行显示
  /// 占位图，点按时仍会解析并跳转。
  static const int _kMaxBookPrefetch = 10;

  UserProfileArgs get _args =>
      ModalRoute.of(context)!.settings.arguments as UserProfileArgs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _loadBooklistsCachedFirst();
    });
  }

  Future<void> _load() async {
    if (ref.read(authProvider).user == null) {
      setState(() {
        _loggedIn = false;
        _isLoading = false;
      });
      return;
    }
    setState(() => _isLoading = true);
    final api = ref.read(zlibraryApiProvider);
    final response =
        await api.getUserComments(_args.userId.toString());
    if (!mounted) return;
    setState(() {
      _entries = response.success && response.data != null
          ? response.data!.entries
          : const [];
      _isLoading = false;
    });
    unawaited(_prefetchBookRefs());
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// 逐本预取书名行的 hash + 封面（串行，避免并发风暴）。同一
  /// bookId 只搜一次；已解析过的跳过；页面销毁即停；单本失败不
  /// 阻塞其余（保持占位图，点按时再试）。
  Future<void> _prefetchBookRefs() async {
    final api = ref.read(zlibraryApiProvider);
    final seen = <int>{};
    var attempts = 0;
    for (final entry in _entries) {
      if (!mounted || attempts >= _kMaxBookPrefetch) return;
      final id = entry.bookId;
      if (id <= 0 || !seen.add(id)) continue;
      if (_bookRefs[id]?.hasHash ?? false) continue;
      attempts++;
      try {
        final info =
            await resolveCommentBookRef(api, id, entry.bookTitle);
        if (!mounted || info == null) continue;
        setState(() => _bookRefs[id] = info);
      } catch (error) {
        // 单本失败保持占位图，点按时重试。
        debugPrint('[user_profile] prefetch ignored ${error.runtimeType}');
      }
    }
  }

  /// 书名行 → 书籍详情。评论接口只给 bookId + 书名，没有书 hash；
  /// 详情页靠 hash 拉全量数据，所以先用标题搜索反查同 id 书目的
  /// eapi hash（[resolveCommentBookRef]，顺带取回封面），再带最小
  /// [Book] 进详情页，由 `bookDetailsProvider` 拉取完整信息。
  /// 预取缓存里有 hash 就不再搜索。
  ///
  /// 解析中该书名行尾转圈；失败提示且不跳转（不进残缺详情页）。
  Future<void> _openBookDetail(UserCommentEntry entry) async {
    if (entry.bookId <= 0 || _openingBookIds.contains(entry.bookId)) {
      return;
    }
    setState(() => _openingBookIds.add(entry.bookId));
    try {
      var hash = _bookRefs[entry.bookId]?.hash ?? '';
      if (hash.isEmpty) {
        final api = ref.read(zlibraryApiProvider);
        final info = await resolveCommentBookRef(
          api,
          entry.bookId,
          entry.bookTitle,
        );
        if (!mounted) return;
        if (info != null) {
          setState(() => _bookRefs[entry.bookId] = info);
          hash = info.hash;
        }
      }
      if (!mounted) return;
      if (hash.isEmpty) {
        _showSnack(AppLocalizations.of(context).get('open_book_failed'));
        return;
      }
      Navigator.of(context).pushNamed(
        AppRoutes.bookDetail,
        arguments: BookDetailArgs(
          book: Book(
            id: entry.bookId,
            title: entry.bookTitle,
            hash: hash,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      debugPrint('[user_profile] open detail ignored ${error.runtimeType}');
      _showSnack(AppLocalizations.of(context).get('open_book_failed'));
    } finally {
      if (mounted) {
        setState(() => _openingBookIds.remove(entry.bookId));
      } else {
        _openingBookIds.remove(entry.bookId);
      }
    }
  }

  /// Pull-to-refresh reloads both sections. The booklists load is
  /// not awaited here: it has its own loading state inside the
  /// section, and its solver fallback can take a while.
  Future<void> _refresh() async {
    _loadBooklists();
    await _load();
  }

  /// Paint the last-known booklists from the persistent cache, then
  /// refresh in the background (stale-while-revalidate). Without a
  /// cached page this is exactly the existing foreground load.
  Future<void> _loadBooklistsCachedFirst() async {
    final hash = _args.userHash;
    if (hash == null || hash.isEmpty) return;
    if (ref.read(authProvider).user == null) return;
    final api = ref.read(zlibraryApiProvider);
    final url = api.userProfilePageUrl(
      userId: _args.userId.toString(),
      userHash: hash,
    );
    final cachedHtml = BooklistHtmlCache.get(url);
    if (cachedHtml != null && !_isChallengeHtml(cachedHtml)) {
      setState(() {
        _booklists = parseUserProfileBooklists(
          cachedHtml,
          baseUrl: Uri.parse(url).origin,
        );
        _booklistsLoading = false;
        _booklistsError = null;
      });
      unawaited(_loadBooklists(backgroundRefresh: true));
      return;
    }
    await _loadBooklists();
  }

  /// The profile document's booklists tab, via the plugin. Skipped
  /// when the tapped comment carried no profile hash — the page then
  /// shows comments only. The profile page is an HTML route, so the
  /// mirror can wall Dio: on a browser-check error the WebView
  /// solver fetches the same page (the booklists screen's pattern).
  /// In background-refresh mode (cached rows on screen) the section
  /// keeps showing them: no loading row, and a failed refresh just
  /// leaves the cached rows in place.
  Future<void> _loadBooklists({bool backgroundRefresh = false}) async {
    final hash = _args.userHash;
    if (hash == null || hash.isEmpty) return;
    if (ref.read(authProvider).user == null) return;
    if (!backgroundRefresh) {
      setState(() {
        _booklistsLoading = true;
        _booklistsError = null;
      });
    }
    final api = ref.read(zlibraryApiProvider);
    try {
      final response = await api.getUserProfileBooklists(
        userId: _args.userId.toString(),
        userHash: hash,
      );
      if (!mounted) return;
      if (response.success && response.data != null) {
        setState(() {
          _booklists = response.data!;
          _booklistsLoading = false;
          _booklistsError = null;
        });
        return;
      }
      if (_isChallengeError(response.error)) {
        await _loadBooklistsViaSolver(
          hash,
          response.error ?? 'Failed to load booklists',
          backgroundRefresh: backgroundRefresh,
        );
        return;
      }
      if (backgroundRefresh) return;
      setState(() {
        _booklistsLoading = false;
        _booklistsError =
            response.error ?? 'Failed to load booklists';
      });
    } catch (e) {
      if (!mounted) return;
      if (backgroundRefresh) return;
      setState(() {
        _booklistsLoading = false;
        _booklistsError = e.toString();
      });
    }
  }

  /// Fetch the profile page through the WebView challenge solver and
  /// parse it with the plugin's [parseUserProfileBooklists]. The
  /// session cookies go into the WebView's CookieManager first (the
  /// booklist detail screen's pattern). A failure here reports the
  /// fast path's original error, so the retry button re-runs the
  /// whole fast-then-solver sequence.
  Future<void> _loadBooklistsViaSolver(
    String hash,
    String originalError, {
    bool backgroundRefresh = false,
  }) async {
    final api = ref.read(zlibraryApiProvider);
    final url = api.userProfilePageUrl(
      userId: _args.userId.toString(),
      userHash: hash,
    );
    final user = ref.read(authProvider).user;
    final userKey = user?.remixUserkey;
    if (user != null && userKey != null && userKey.isNotEmpty) {
      await _installSessionCookies(user.id, userKey, url);
    }
    var html = ChallengeHtmlCache.get(url);
    if (html != null && _isChallengeHtml(html)) {
      // A stale challenge page must not short-circuit the solve.
      html = null;
    }
    html ??= await WebviewChallengeSolver.fetchHtmlAfterChallenge(url);
    if (!mounted) return;
    if (html == null || html.isEmpty || _isChallengeHtml(html)) {
      if (backgroundRefresh) return;
      setState(() {
        _booklistsLoading = false;
        _booklistsError = originalError;
      });
      return;
    }
    // `html` is a mutable local captured by the setState closure
    // below, so its null-check promotion does not survive into the
    // closure — pin it to a final first.
    final pageHtml = html;
    // The solve earned wall-clearance cookies — hand them to Dio so
    // the next HTML load skips the solver. The solved page also goes
    // into the persistent cache so the next open paints it instantly.
    await bridgeWallCookies(api, url);
    if (!mounted) return;
    BooklistHtmlCache.store(url, pageHtml);
    setState(() {
      _booklists = parseUserProfileBooklists(
        pageHtml,
        baseUrl: Uri.parse(url).origin,
      );
      _booklistsLoading = false;
      _booklistsError = null;
    });
  }

  /// The plugin's short error for a browser-check wall
  /// ('HTTP 503: browser check page'), plus the older shapes a wall can
  /// surface as, so the solver fallback triggers on any of them.
  bool _isChallengeError(String? error) {
    if (error == null) return false;
    final lower = error.toLowerCase();
    return lower.contains('browser check') ||
        lower.contains('checking your browser') ||
        lower.contains('ddos-guard') ||
        lower.contains('cf_blocked') ||
        lower.contains('cf-challenge');
  }

  /// The solver only completes on real pages, but a cached page can be
  /// a stale challenge page — never parse one as an (empty) booklists
  /// page.
  bool _isChallengeHtml(String html) =>
      WebviewChallengeSolver.isChallengeHtml(html);

  /// Install the `remix_userid` / `remix_userkey` session into the
  /// WebView's CookieManager for the profile page's host (the reader's
  /// pattern — the manager is global on Android, so the solver's
  /// headless WebView sees them). Never put the keys in a URL.
  Future<void> _installSessionCookies(
    String userId,
    String userKey,
    String pageUrl,
  ) async {
    final uri = Uri.tryParse(pageUrl);
    if (uri == null || uri.host.isEmpty) return;
    final manager = CookieManager.instance();
    final url = WebUri('https://${uri.host}/');
    await manager.setCookie(
      url: url,
      name: 'remix_userid',
      value: userId,
      isSecure: true,
      isHttpOnly: true,
    );
    await manager.setCookie(
      url: url,
      name: 'remix_userkey',
      value: userKey,
      isSecure: true,
      isHttpOnly: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final args = _args;

    return Scaffold(
      appBar: GradientAppBar(title: args.userName),
      body: _isLoading
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
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
                    children: [
                      _ProfileHeader(
                        args: args,
                        commentCount: _entries.length,
                        booklistCount: _booklistCount,
                      ),
                      ..._booklistsSection(),
                      _sectionHeader(
                        l10n.get('comments'),
                        _entries.length,
                      ),
                      ..._commentCards(),
                    ],
                  ),
                ),
    );
  }

  /// 头部统计的书单数：无书单区（评论没带 hash）或加载中/出错时
  /// 返回 null，头部就不显示书单药丸。
  int? get _booklistCount {
    final hash = _args.userHash;
    if (hash == null || hash.isEmpty) return null;
    if (_booklistsLoading || _booklistsError != null) return null;
    return _booklists.length;
  }

  Widget _sectionHeader(String title, int? count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        count == null ? title : '$title ($count)',
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }

  /// The booklists section: header + rows, a loading row while the
  /// profile document loads, a short line when the user has none,
  /// and an error row with a retry button when both the fast path
  /// and the solver failed. Empty when the tapped comment carried
  /// no profile hash — the page then shows comments only.
  List<Widget> _booklistsSection() {
    final l10n = AppLocalizations.of(context);
    final hash = _args.userHash;
    if (hash == null || hash.isEmpty) return const [];
    final children = <Widget>[
      _sectionHeader(
        l10n.get('booklists'),
        _booklistsLoading || _booklistsError != null
            ? null
            : _booklists.length,
      ),
    ];
    if (_booklistsLoading) {
      children.add(const LoadingWidget.more());
    } else if (_booklistsError != null) {
      children.add(_booklistsErrorRow());
    } else if (_booklists.isEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            l10n.get('no_booklists'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    } else {
      // 书单分组成一张圆角卡：行间细分隔线，与评论卡片同一套语言。
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < _booklists.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 72),
                  BooklistRow(
                    list: _booklists[i],
                    onTap: () => Navigator.of(context).pushNamed(
                      AppRoutes.booklistDetail,
                      arguments:
                          BooklistDetailArgs(booklist: _booklists[i]),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return children;
  }

  Widget _booklistsErrorRow() {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 20, color: cs.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _booklistsError ?? l10n.get('error'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: _loadBooklists,
            child: Text(l10n.get('retry')),
          ),
        ],
      ),
    );
  }

  /// The comment cards, 12 px apart like "My Comments" — or a single
  /// short line when the user has posted none (a full empty state
  /// would hide the booklists above).
  List<Widget> _commentCards() {
    if (_entries.isEmpty) {
      final l10n = AppLocalizations.of(context);
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            l10n.get('no_comments'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ];
    }
    final args = _args;
    final cards = <Widget>[];
    for (var i = 0; i < _entries.length; i++) {
      final entry = _entries[i];
      if (i > 0) cards.add(const SizedBox(height: 12));
      cards.add(
        _ProfileCommentCard(
          entry: entry,
          userName: args.userName,
          coverUrl: _bookRefs[entry.bookId]?.cover ?? '',
          isOpeningBook: _openingBookIds.contains(entry.bookId),
          onCardTap: () => Navigator.of(context).pushNamed(
            AppRoutes.bookComments,
            arguments: BookCommentsArgs(
              bookId: entry.bookId,
              bookTitle: entry.bookTitle,
            ),
          ),
          onBookTap: () => _openBookDetail(entry),
        ),
      );
    }
    return cards;
  }
}

/// 主页头部卡片：头像 + 昵称 + 统计药丸（评论数 / 书单数）。评论数
/// 来自评论接口，书单数来自书单区（加载中或无书单区时省略）。
/// 头像与昵称就是点进来的那条评论所见，无需再取。
class _ProfileHeader extends StatelessWidget {
  final UserProfileArgs args;
  final int commentCount;
  final int? booklistCount;

  const _ProfileHeader({
    required this.args,
    required this.commentCount,
    required this.booklistCount,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CommentAvatar(avatarUrl: args.userAvatar, radius: 32),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      args.userName,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _StatPill(
                    icon: Icons.comment_outlined,
                    count: commentCount,
                  ),
                  if (booklistCount != null) ...[
                    const SizedBox(width: 8),
                    _StatPill(
                      icon: Icons.collections_bookmark_outlined,
                      count: booklistCount!,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 头部统计药丸：图标 + 数字（等宽数字，数字变化不跳动）。
class _StatPill extends StatelessWidget {
  final IconData icon;
  final int count;

  const _StatPill({required this.icon, required this.count});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.onSecondaryContainer),
          const SizedBox(width: 5),
          Text(
            count.toString(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: cs.onSecondaryContainer,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// 卡片化的一条主页评论，与“我的评论”页同一套视觉语言：
/// 书名行（封面缩略图 + 书名，点击 → 书籍详情）+ 头像/昵称/正文/
/// 日期与获赞数。点卡片其余区域进入该书的评论区；头像不可点——
/// 当前页就是这位用户的主页。
class _ProfileCommentCard extends StatelessWidget {
  final UserCommentEntry entry;
  final String userName;

  /// 书名行的封面 URL；空串显示占位图（hash/封面未解析到）。
  final String coverUrl;

  /// 书 hash 解析中：书名行尾显示转圈并禁止再次点击。
  final bool isOpeningBook;
  final VoidCallback onCardTap;
  final VoidCallback onBookTap;

  const _ProfileCommentCard({
    required this.entry,
    required this.userName,
    required this.coverUrl,
    required this.isOpeningBook,
    required this.onCardTap,
    required this.onBookTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final comment = entry.comment;
    final date = comment.dateRelative.isNotEmpty
        ? comment.dateRelative
        : comment.date;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onCardTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 书名行 → 书籍详情（内层命中优先于卡片）。
                CommentBookTile(
                  title: entry.bookTitle,
                  coverUrl: coverUrl,
                  busy: isOpeningBook,
                  onTap: onBookTap,
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CommentAvatar(avatarUrl: comment.userAvatar),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userName,
                            style: tt.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (comment.text.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            SelectableText(
                              comment.text,
                              style: tt.bodyMedium?.copyWith(height: 1.45),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text(
                                date,
                                style: tt.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 6),
                              CommentMetricChip(
                                // 描边图标与评论区一致；纯展示获赞数，
                                // 不支持点赞切换。
                                icon: Icons.thumb_up_outlined,
                                count: comment.likeCount,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
