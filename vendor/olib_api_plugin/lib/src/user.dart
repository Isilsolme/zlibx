/// The logged-in Z-Library account.
///
/// `id` is a String here on purpose: the app stores it as a string
/// credential (`AuthStorage.saveCredentials(userId: user.id, ...)`) and
/// sends it back as the `remix_userid` cookie / query value, while the
/// server sometimes returns it as a number. [fromJson] coerces either way.
///
/// `downloadsLeft` defaults to 0: the app only constructs a [User] itself
/// for a cached, unverified session (auth fallback), and every place that
/// reads `downloadsLeft` re-checks a freshly fetched profile before
/// treating 0 as "quota exhausted".
class User {
  final String id;
  final String email;
  final String name;
  final String remixUserkey;
  final int downloadsLeft;

  const User({
    required this.id,
    required this.email,
    required this.name,
    required this.remixUserkey,
    this.downloadsLeft = 0,
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
  /// endpoints: a direct `downloads_left`, or a `limits` object holding
  /// either a remaining count or a used/total pair.
  static int _downloadsLeft(Map<String, dynamic> json) {
    final direct = _asInt(
      json['downloadsLeft'] ?? json['downloads_left'],
    );
    if (direct != null) return direct;
    final limits = json['limits'];
    if (limits is Map<String, dynamic>) {
      final remaining = _asInt(
        limits['downloads_left'] ?? limits['downloadsLeft'] ?? limits['remaining'],
      );
      if (remaining != null) return remaining;
      final total = _asInt(limits['downloads'] ?? limits['limit']);
      final used = _asInt(limits['used'] ?? limits['downloads_used']);
      if (total != null && used != null) return total - used;
    }
    return 0;
  }
}
