import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/hive_service.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';
import 'auth_provider.dart';
import 'cache_invalidation.dart';
import 'zlibrary_provider.dart';

const defaultDomain = 'bookroom.lifestyle';
const _retiredBuiltInDomains = {
  'zlibraryf.online',
  'zlibraryh.online',
  'zlibraryd.online',
  'zlibrary6.online',
  'zlibraryg.online',
  '777495.best',
  'freezlib.me',
  'sibaihua.pro',
  'pkuedu.online',
  '101intj.ru',
  '101w.online',
  'zlibraryj.online',
  'biblioteca.pro',
};

/// All available mirror domains (flat list).
const kBuiltInDomains = [
  'bookroom.lifestyle',
  'bibliotheca.world',
  'bibliotheca.study',
  'bibliotheca.lifestyle',
  'luto.top',
  'bibliotheca.life',
  'anthology.lifestyle',
  'elaborate.monster',
  's0u1.top',
  '26h2.tech',
  'orangerain.space',
  'zouwu.top',
  'xn--t8j0bxa8hymnb.jp',
  '553211.xyz',
  'loves.works',
  'z-library.im',
  'ireadhuang.sbs',
  'elaborate.quest',
  'elaborate.wtf',
  '9libmirror.tech',
  'shunfei.shop',
  'elaboratethinking.online',
  'bookorg.tech',
  'booook.me',
  '95427279.xyz',
  'zkoo.site',
  'adsblaze.com',
  '817523.xyz',
  'toffeeboba.com',
  'interflow.ch',
  'free2read.cc',
  '8964520.xyz',
  'umq.me',
  '110434.xyz',
  'frank9527.site',
  'freebooks.lol',
  '226272.xyz',
  'jdbooks.xyz',
  'arcfoxxxxxx.site',
  '86110101.xyz',
  '909190.xyz',
];

final domainListProvider = Provider<List<String>>((ref) {
  return kBuiltInDomains;
});

final domainProvider =
    NotifierProvider<DomainNotifier, String>(DomainNotifier.new);

class DomainNotifier extends Notifier<String> {
  late final ZLibraryApi _api;

  @override
  String build() {
    _api = ref.read(zlibraryApiProvider);
    final initial = _initialDomain();
    if (HiveService.settingsBox.get('domain') != initial) {
      HiveService.settingsBox.put('domain', initial);
    }
    // Ensure API is in sync with initial state (no side effects: auth init
    // handles cookie setup on first boot).
    _api.setDomain(initial);
    return initial;
  }

  static String _initialDomain() {
    final saved = HiveService.settingsBox.get('domain') as String?;
    if (saved == null || _retiredBuiltInDomains.contains(saved)) {
      return defaultDomain;
    }
    return saved;
  }

  /// Switch to a new line. Fire-and-forget: callers don't need to await.
  /// Internally we re-establish cookies on the new domain (reverify) and
  /// invalidate data providers so they refetch against the new line.
  ///
  /// [reverifySession] must be false for non-built-in domains: the stored
  /// session is never auto-sent to an arbitrary host. The line is flagged
  /// unavailable instead, and the user logs in again explicitly if they
  /// trust the domain.
  void setDomain(String domain, {bool reverifySession = true}) {
    if (domain == state) return;
    state = domain;
    HiveService.settingsBox.put('domain', domain);
    // The in-memory session must not follow the user to a new host; trusted
    // (built-in) hosts get it back through reverify() below.
    _api.clearSession();
    _api.setDomain(domain);
    _refreshAfterSwitch(reverifySession: reverifySession);
  }

  /// A custom domain is valid when it is a plain hostname (or IPv4) with
  /// an optional port — no userinfo, path, query or fragment.
  static bool isValidCustomDomain(String domain) {
    final d = domain.trim();
    if (d.isEmpty || d.length > 253) return false;
    if (d.contains(RegExp(r'[\s/@?#;]'))) return false;
    final parts = d.split(':');
    if (parts.length > 2) return false;
    if (parts.length == 2) {
      final port = int.tryParse(parts[1]);
      if (port == null || port < 1 || port > 65535) return false;
    }
    final host = parts.first;
    if (host.isEmpty) return false;
    // IPv4.
    if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host)) {
      final o = host.split('.').map((p) => int.tryParse(p) ?? 256).toList();
      if (o.any((n) => n > 255)) return false;
      // 回环 / 0.0.0.0 / 链路本地（含云元数据 169.254.169.254）不是镜像站。
      if (o[0] == 0 || o[0] == 127 || (o[0] == 169 && o[1] == 254)) {
        return false;
      }
      return true;
    }
    // DNS hostname: dot-separated labels, no leading/trailing hyphen/dot.
    if (host.startsWith('.') ||
        host.endsWith('.') ||
        host.startsWith('-') ||
        host.endsWith('-')) {
      return false;
    }
    final label = RegExp(r'^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$');
    return host.split('.').every((part) => label.hasMatch(part));
  }

  static bool isBuiltInDomain(String domain) {
    final host = domain.trim().split(':').first.toLowerCase();
    return host == defaultDomain || kBuiltInDomains.contains(host);
  }

  /// Strip scheme and any path / query / fragment a pasted URL may carry.
  static String normalizeCustomDomain(String domain) {
    var clean = domain.trim().replaceAll(RegExp(r'^https?://'), '');
    final cut = clean.indexOf(RegExp(r'[/?#]'));
    if (cut >= 0) clean = clean.substring(0, cut);
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    return clean.toLowerCase();
  }

  /// Validate + switch to a custom line. Returns false when the input is
  /// not a valid domain (caller keeps the dialog open). Non-built-in
  /// domains switch WITHOUT re-sending the stored session.
  bool setCustomDomain(String domain) {
    final cleanDomain = normalizeCustomDomain(domain);
    if (!isValidCustomDomain(cleanDomain)) return false;
    setDomain(
      cleanDomain,
      reverifySession: isBuiltInDomain(cleanDomain),
    );
    return true;
  }

  Future<void> _refreshAfterSwitch({required bool reverifySession}) async {
    if (reverifySession) {
      // Cookies are domain-scoped — re-issue remix_userid/remix_userkey on the
      // new domain and re-fetch profile. This also clears the lineUnavailable
      // flag on success.
      await ref.read(authProvider.notifier).reverify();
    } else {
      // Custom domain: do NOT send the stored session here. Flag the line
      // unavailable so the user explicitly logs in again if they trust it.
      ref.read(authProvider.notifier).flagLineUnavailable();
    }
    // Bust caches for anything that depends on the line. The shared list
    // (see cache_invalidation.dart) grew out of three hand-copied blocks
    // that had already drifted apart — keep one list, not three.
    invalidateAccountScopedProviders(ref);
  }
}
