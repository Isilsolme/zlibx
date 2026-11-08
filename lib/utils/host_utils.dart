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
