/// Second-level labels of the Z-Library site family. A host belongs to the
/// family only when its registrable label (the one right before the TLD)
/// is one of these, e.g. `z-library.sk`, `reader.z-lib.fm`,
/// `bookroom.lifestyle`, `singlelogin.re`.
const _zlibFamilyLabels = {'z-library', 'z-lib', 'bookroom', 'singlelogin'};

/// Whether [rawHost] is a Z-Library family host.
///
/// This replaces a loose `host.contains('z-library')` check, which also
/// accepted look-alike hosts such as `z-library.evil.com` or
/// `notbookroom.xyz`. Only the label directly before the TLD counts.
bool isZlibFamilyHost(String rawHost) {
  final host = rawHost.trim().toLowerCase();
  if (host.isEmpty || host.contains(':') || host.contains('/')) return false;
  final labels = host.split('.');
  if (labels.length < 2 || labels.any((l) => l.isEmpty)) return false;
  return _zlibFamilyLabels.contains(labels[labels.length - 2]);
}

/// Language prefixes some mirrors put in front of the domain
/// (`zh.z-lib.fm`); the reader never lives under them.
const _readerLangPrefixes = {
  'zh', 'en', 'de', 'fr', 'es', 'it', 'pt', 'ja', 'ko', 'ru', 'ar',
};

/// Reader host for the current line [lineDomain]:
/// `z-lib.fm` -> `reader.z-lib.fm`, `zh.z-lib.fm` -> `reader.z-lib.fm`.
String readerDomainFor(String lineDomain) {
  final dot = lineDomain.indexOf('.');
  if (dot > 0 && _readerLangPrefixes.contains(lineDomain.substring(0, dot))) {
    return 'reader${lineDomain.substring(dot)}';
  }
  return 'reader.$lineDomain';
}

/// Whether [url] is a reader page of the current line [lineDomain]: https,
/// no userinfo, and a host that is the line's reader host or inside the
/// line's own domain.
///
/// `Book.readOnlineUrl` comes from the server response, so it must never
/// decide where the session cookies (`remix_userkey`) get written: a
/// mirror (or a tampered response) could name any host there.
bool isTrustedReaderUrl(String url, String lineDomain) {
  // A custom line may carry a port (`host:8443`); Uri.host never does.
  final line = lineDomain.trim().toLowerCase().split(':').first;
  if (line.isEmpty) return false;
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
    return false;
  }
  final host = uri.host.toLowerCase();
  if (host.isEmpty) return false;
  final reader = readerDomainFor(line);
  final bare = reader.substring('reader.'.length);
  return host == reader ||
      host == bare ||
      host.endsWith('.$bare') ||
      host == line ||
      host.endsWith('.$line');
}
