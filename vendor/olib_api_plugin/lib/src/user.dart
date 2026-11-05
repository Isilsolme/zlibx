/// The logged-in Z-Library account.
///
/// `id` is a String here on purpose: the app stores it as a string
/// credential (`AuthStorage.saveCredentials(userId: user.id, ...)`) and
/// sends it back as the `remix_userid` cookie / query value, while the
/// server sometimes returns it as a number. [fromJson] coerces either way.
///
/// `downloadsLeft` is nullable: `null` means the quota is unknown, which
/// must NOT be treated as "quota exhausted". The real profile payload
/// (`GET /eapi/user/profile`) carries `downloads_today` /
/// `downloads_limit` (fallbacks `dailyDownloadsCount` /
/// `dailyDownloadLimit`); remaining = limit - today. Older shapes
/// (`downloads_left`, a `limits` object) are still accepted. When none of
/// them is present, the value stays `null` instead of defaulting to 0 —
/// a 0 default made every quota check conclude "exhausted" and blocked
/// downloads that never even started.
class User {
  final String id;
  final String email;
  final String name;
  final String remixUserkey;
  final int? downloadsLeft;

  const User({
    required this.id,
    required this.email,
    required this.name,
    required this.remixUserkey,
    this.downloadsLeft,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: _asString(json['id'] ?? json['userId'] ?? json['user_id']) ?? '',
      email: _asString(json['email']) ?? '',
      name: _asString(json['name'] ?? json['username']) ?? '',
      remixUserkey: _asString(
        json['remixUserkey'] ?? json['remix_userkey'] ?? json['userKey'],
      ) ?? '',
      downloadsLeft: _downloadsLeft(json),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'name': name,
    'remixUserkey': remixUserkey,
    'downloadsLeft': downloadsLeft,
  };

  static String? _asString(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    return v.toString();
  }

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString());
  }

  /// The profile payload spells the remaining quota several ways across
  /// endpoints. The real `/eapi/user/profile` shape (verified against the
  /// zlib reference client) is a used/limit pair on the user object:
  /// `downloads_today` / `downloads_limit`, with `dailyDownloadsCount` /
  /// `dailyDownloadLimit` as fallbacks. A direct `downloads_left` or a
  /// `limits` object is accepted for older shapes. Returns `null` when
  /// the payload carries no quota information at all.
  static int? _downloadsLeft(Map<String, dynamic> json) {
    final direct = _asInt(
      json['downloadsLeft'] ?? json['downloads_left'],
    );
    if (direct != null) return direct;
    final limit = _asInt(
      json['downloads_limit'] ??
          json['downloadsLimit'] ??
          json['dailyDownloadLimit'],
    );
    final used = _asInt(
      json['downloads_today'] ??
          json['downloadsToday'] ??
          json['dailyDownloadsCount'],
    );
    if (limit != null && used != null) {
      final remaining = limit - used;
      return remaining < 0 ? 0 : remaining;
    }
    final limits = json['limits'];
    if (limits is Map<String, dynamic>) {
      final remaining = _asInt(
        limits['downloads_left'] ?? limits['downloadsLeft'] ?? limits['remaining'],
      );
      if (remaining != null) return remaining;
      final total = _asInt(limits['downloads'] ?? limits['limit']);
      final usedInLimits = _asInt(limits['used'] ?? limits['downloads_used']);
      if (total != null && usedInLimits != null) {
        final remainingFromPair = total - usedInLimits;
        return remainingFromPair < 0 ? 0 : remainingFromPair;
      }
    }
    return null;
  }
}
