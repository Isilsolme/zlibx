import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:awesome_dialog/awesome_dialog.dart';
import '../../providers/auth_provider.dart';
import '../../providers/domain_provider.dart';
import '../../routes/app_routes.dart';
import '../../services/update_service.dart';
import '../../widgets/domain_selector.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/update_dialog.dart';
import '../../l10n/app_localizations.dart';
import 'widgets/account_manager_sheet.dart';
import 'login_failure.dart';

class LoginScreen extends ConsumerStatefulWidget {
  final bool addAccountMode;

  const LoginScreen({super.key, this.addAccountMode = false});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  List<Map<String, dynamic>> _savedAccounts = const [];
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Check for updates after frame is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
      _loadSavedAccounts(prefillCredentials: !widget.addAccountMode);
    });
  }

  Future<void> _checkForUpdates() async {
    final hasUpdate = await UpdateService.checkForUpdate(force: true);

    if (!hasUpdate || !mounted) return;


    if (UpdateService.forceUpdate) {
      // Force update - non-dismissable dialog with download channels
      showUpdateDialog(context);
    } else {
      // Normal update - just show info snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).get('new_version_found').replaceAll('{version}', '${UpdateService.latestVersion}'),
          ),
          action: SnackBarAction(
            label: AppLocalizations.of(context).get('update'),
            onPressed: () => showUpdateDialog(context),
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _loadSavedAccounts({bool prefillCredentials = false}) async {
    final accounts = await ref.read(authProvider.notifier).getSavedAccounts();
    if (!mounted) return;

    final savedAccounts = accounts
        .map((account) => Map<String, dynamic>.from(account))
        .toList();

    if (prefillCredentials &&
        savedAccounts.isNotEmpty &&
        _emailController.text.isEmpty &&
        _passwordController.text.isEmpty &&
        !_isLoading) {
      final lastAccount = savedAccounts.last;
      final email = lastAccount['email'] as String?;

      // Passwords are never persisted: only the email can be prefilled.
      if (email != null && email.isNotEmpty) {
        _emailController.text = email;
      }
    }

    setState(() => _savedAccounts = savedAccounts);
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final currentDomain = ref.read(domainProvider);
    final lineIndex = ref.read(domainListProvider).indexOf(currentDomain);
    final lineName = lineIndex >= 0 ? 'Line ${lineIndex + 1}' : 'Custom';
    setState(() => _isLoading = true);

    final success = await ref
        .read(authProvider.notifier)
        .login(email, password);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      _navigateAfterAuthentication();
    } else {
      final error = ref.read(authProvider).error;
      final occurredAt = DateTime.now().toLocal().toIso8601String().split('.').first;

      final failureKind = classifyLoginFailure(error);
      if (failureKind == LoginFailureKind.line) {
        // 线路被拦截 / 连接失败 —— 不是账号密码问题，提示切换线路。
        final cf = error == 'cf_blocked';
        AwesomeDialog(
          context: context,
          dialogType: DialogType.warning,
          animType: AnimType.bottomSlide,
          title: AppLocalizations.of(context).get('line_unavailable'),
          desc: AppLocalizations.of(context).get(
              cf ? 'login_line_blocked_cf' : 'login_line_connect_failed'),
          btnCancelText: AppLocalizations.of(context).get('close'),
          btnCancelOnPress: () {},
          btnOkText: AppLocalizations.of(context).get('switch_line'),
          btnOkColor: Theme.of(context).colorScheme.primary,
          btnOkOnPress: () {
            showDialog(
              context: context,
              builder: (_) => const DomainSelectionDialog(),
            );
          },
        ).show();
      } else {
        AwesomeDialog(
          context: context,
          dialogType: DialogType.error,
          animType: AnimType.bottomSlide,
          title: AppLocalizations.of(context).get('login_failed'),
          desc: failureKind == LoginFailureKind.credentials
              ? (AppLocalizations.of(context).get('login_bad_credentials'))
              : (AppLocalizations.of(context).get('login_unknown_failure').replaceAll('{line}', '$lineName').replaceAll('{time}', '$occurredAt').replaceAll('{detail}', safeLoginErrorDetail(error, email, password))),
          btnOkText: AppLocalizations.of(context).get('confirm_ok'),
          btnOkColor: Theme.of(context).colorScheme.primary,
          btnOkOnPress: () {},
        ).show();
      }
    }
  }

  Future<void> _showSavedAccounts() async {
    final currentUserId = widget.addAccountMode
        ? ref.read(authProvider).user?.id.toString()
        : null;
    final result = await showAccountManagerSheet(
      context,
      currentUserId: currentUserId,
    );
    if (!mounted) return;

    await _loadSavedAccounts();
    if (!mounted) return;

    switch (result) {
      case AccountManagerResult.switched:
        _navigateAfterAuthentication();
      case AccountManagerResult.addAccount:
        _emailController.clear();
        _passwordController.clear();
        _emailFocusNode.requestFocus();
      case null:
        break;
    }
  }

  void _navigateAfterAuthentication() {
    if (widget.addAccountMode) {
      Navigator.of(context).pop(true);
    } else {
      Navigator.of(context).pushReplacementNamed(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 16),
            child: DomainSelector(compact: true, color: Colors.white),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.book,
                      size: 60,
                      color: Colors.white,
                    ),
                  ),

                  const SizedBox(height: 24),

                  Text(
                    AppLocalizations.of(context).get(
                      widget.addAccountMode ? 'add_account' : 'welcome_back',
                    ),
                    style: Theme.of(
                      context,
                    ).textTheme.displayMedium?.copyWith(color: Colors.white),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    AppLocalizations.of(context).get(
                      widget.addAccountMode
                          ? 'add_account_subtitle'
                          : 'login_to_continue',
                    ),
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Open Source & Free badges
                  _buildBadges(context),

                  const SizedBox(height: 32),

                  // Login Form
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          if (_savedAccounts.isNotEmpty) ...[
                            _buildRecentAccountEntry(context),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                const Expanded(child: Divider()),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  child: Text(
                                    AppLocalizations.of(
                                      context,
                                    ).get('use_another_account'),
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ),
                                const Expanded(child: Divider()),
                              ],
                            ),
                            const SizedBox(height: 20),
                          ],
                          TextFormField(
                            controller: _emailController,
                            focusNode: _emailFocusNode,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              labelText: AppLocalizations.of(
                                context,
                              ).get('email'),
                              prefixIcon: const Icon(Icons.email_outlined),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your email';
                              }
                              if (!value.contains('@')) {
                                return 'Please enter a valid email';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 16),

                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: AppLocalizations.of(
                                context,
                              ).get('password'),
                              prefixIcon: const Icon(Icons.lock_outlined),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your password';
                              }
                              if (value.length < 6) {
                                return 'Password must be at least 6 characters';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 32),

                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _handleLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(context).colorScheme.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                              ),
                              child: _isLoading
                                  ? const LoadingWidget.inline(
                                      color: Colors.white,
                                    )
                                  : Text(
                                      AppLocalizations.of(context).get('login'),
                                    ),
                            ),
                          ),
                          if (_savedAccounts.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _isLoading ? null : _showSavedAccounts,
                              icon: const Icon(Icons.manage_accounts_outlined),
                              label: Text(
                                AppLocalizations.of(
                                  context,
                                ).get('manage_accounts'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Hint: Use Z站 official account
                  _buildAccountHint(context),

                  const SizedBox(height: 16),

                  // Skip login — enter Home without account
                  _buildSkipLogin(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentAccountEntry(BuildContext context) {
    final account = _savedAccounts.last;
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final name = account['name']?.toString().trim();
    final email = account['email']?.toString().trim();
    final displayName = name == null || name.isEmpty
        ? l10n.get('unknown')
        : name;

    return Material(
      color: cs.primaryContainer.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _isLoading ? null : _showSavedAccounts,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                child: Text(displayName.substring(0, 1).toUpperCase()),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.get('recent_account'),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (email != null && email.isNotEmpty)
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccountHint(BuildContext context) {

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.info_outline,
                color: Colors.white.withValues(alpha: 0.8),
                size: 16,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  AppLocalizations.of(context).get('login_use_zsite_account'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context).get('login_no_account_hint'),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSkipLogin(BuildContext context) {

    return TextButton(
      onPressed: () {
        Navigator.of(context).pushReplacementNamed(AppRoutes.home);
      },
      child: Text(
        AppLocalizations.of(context).get('login_skip_explore'),
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.7),
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildBadges(BuildContext context) {

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildBadge(
          icon: Icons.code,
          text: AppLocalizations.of(context).get('badge_open_source'),
          color: Colors.green,
        ),
        _buildBadge(
          icon: Icons.money_off,
          text: AppLocalizations.of(context).get('search_free'),
          color: Colors.blue,
        ),
        _buildBadge(
          icon: Icons.smart_toy_outlined,
          text: AppLocalizations.of(context).get('badge_ai_built'),
          color: Colors.purple,
        ),
      ],
    );
  }

  Widget _buildBadge({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
