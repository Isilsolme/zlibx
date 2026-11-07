import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/zlibrary_provider.dart';
import '../../routes/app_routes.dart';
import '../../services/challenge_html_cache.dart';
import '../../services/wall_cookie_bridge.dart';
import '../../services/webview_challenge_solver.dart';
import '../../widgets/booklist_row.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/gradient_app_bar.dart';
import '../../widgets/loading_widget.dart';
import '../comments/book_comments_screen.dart';
import 'booklist_detail_screen.dart';

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
/// comments page; tapping a booklist opens its detail page, with
/// the carousel preview painting instantly.
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

  UserProfileArgs get _args =>
      ModalRoute.of(context)!.settings.arguments as UserProfileArgs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _loadBooklists();
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
  }

  /// Pull-to-refresh reloads both sections. The booklists load is
  /// not awaited here: it has its own loading state inside the
  /// section, and its solver fallback can take a while.
  Future<void> _refresh() async {
    _loadBooklists();
    await _load();
  }

  /// The profile document's booklists tab, via the plugin. Skipped
  /// when the tapped comment carried no profile hash — the page then
  /// shows comments only. The profile page is an HTML route, so the
  /// mirror can wall Dio: on a browser-check error the WebView
  /// solver fetches the same page (the booklists screen's pattern).
  Future<void> _loadBooklists() async {
    final hash = _args.userHash;
    if (hash == null || hash.isEmpty) return;
    if (ref.read(authProvider).user == null) return;
    setState(() {
      _booklistsLoading = true;
      _booklistsError = null;
    });
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
        });
        return;
      }
      if (_isChallengeError(response.error)) {
        await _loadBooklistsViaSolver(
          hash,
          response.error ?? 'Failed to load booklists',
        );
        return;
      }
      setState(() {
        _booklistsLoading = false;
        _booklistsError =
            response.error ?? 'Failed to load booklists';
      });
    } catch (e) {
      if (!mounted) return;
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
    String originalError,
  ) async {
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
      setState(() {
        _booklistsLoading = false;
        _booklistsError = originalError;
      });
      return;
    }
    // The solve earned wall-clearance cookies — hand them to Dio so
    // the next HTML load skips the solver.
    await bridgeWallCookies(api, url);
    setState(() {
      _booklists = parseUserProfileBooklists(
        html,
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
  /// page. Uses the solver's own detector, with the title pulled out
  /// of the HTML (the solver checks the title for 'checking your
  /// browser').
  bool _isChallengeHtml(String html) {
    final titleMatch = RegExp(
      r'<title[^>]*>(.*?)</title>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);
    return WebviewChallengeSolver.isChallengePage(
      title: titleMatch?.group(1) ?? '',
      bodySnippet: html,
    );
  }

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
    final userHash = args.userHash;

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
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      _ProfileHeader(args: args),
                      const Divider(height: 1),
                      ..._booklistsSection(),
                      if (userHash != null && userHash.isNotEmpty)
                        const Divider(height: 1),
                      _sectionHeader(
                        l10n.get('comments'),
                        _entries.length,
                      ),
                      ..._commentRows(),
                    ],
                  ),
                ),
    );
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
      for (var i = 0; i < _booklists.length; i++) {
        if (i > 0) {
          children.add(const Divider(height: 1, indent: 72));
        }
        final list = _booklists[i];
        children.add(
          BooklistRow(
            list: list,
            onTap: () => Navigator.of(context).pushNamed(
              AppRoutes.booklistDetail,
              arguments: BooklistDetailArgs(booklist: list),
            ),
          ),
        );
      }
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

  /// The comment cards, separated by dividers — or a single short
  /// line when the user has posted none (a full empty state would
  /// hide the booklists above).
  List<Widget> _commentRows() {
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
    final rows = <Widget>[];
    for (var i = 0; i < _entries.length; i++) {
      if (i > 0) {
        rows.add(const Divider(height: 1, indent: 68));
      }
      final entry = _entries[i];
      rows.add(
        _ProfileCommentCard(
          entry: entry,
          userName: args.userName,
          onTap: () => Navigator.of(context).pushNamed(
            AppRoutes.bookComments,
            arguments: BookCommentsArgs(
              bookId: entry.bookId,
              bookTitle: entry.bookTitle,
            ),
          ),
        ),
      );
    }
    return rows;
  }
}

/// Avatar + name of the profile user. The comments endpoint carries
/// no profile header, so this is exactly what the tapped comment
/// showed — nothing is fetched for it.
class _ProfileHeader extends StatelessWidget {
  final UserProfileArgs args;

  const _ProfileHeader({required this.args});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: cs.primaryContainer,
            backgroundImage: args.userAvatar.isNotEmpty
                ? NetworkImage(args.userAvatar)
                : null,
            child: args.userAvatar.isEmpty
                ? Icon(
                    Icons.person_rounded,
                    color: cs.onPrimaryContainer,
                    size: 36,
                  )
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              args.userName,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
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

/// Same row styling as "My Comments": book header, avatar + name,
/// text, and a bottom row with the date on the left and a read-only
/// like count on the right. The avatar here is not tappable — it is
/// already this profile's user.
class _ProfileCommentCard extends StatelessWidget {
  final UserCommentEntry entry;
  final String userName;
  final VoidCallback onTap;

  const _ProfileCommentCard({
    required this.entry,
    required this.userName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final comment = entry.comment;
    final date = comment.dateRelative.isNotEmpty
        ? comment.dateRelative
        : comment.date;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.book_outlined, color: cs.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.bookTitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
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
                        userName,
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
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.thumb_up_outlined,
                            size: 16,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            comment.likeCount.toString(),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
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
    );
  }
}
