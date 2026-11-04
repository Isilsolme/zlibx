/// Generic wrapper for one Z-Library API call.
///
/// The app only reads [success], [data], [error] and [meta]:
/// - `search` / `getUserSaved` read `meta['total_pages']` for pagination.
/// - auth code treats `error == 'cf_blocked'` (and transient network
///   substrings) specially, so error strings are kept stable, see
///   `zlibrary_api.dart`.
class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? error;
  final int? statusCode;

  /// Pagination / extra fields from the server, e.g. `{'total_pages': 12}`.
  /// Kept as the raw map so callers can read keys the server adds later.
  final Map<String, dynamic>? meta;

  const ApiResponse({
    required this.success,
    this.data,
    this.error,
    this.statusCode,
    this.meta,
  });

  factory ApiResponse.ok(T data, {Map<String, dynamic>? meta}) =>
      ApiResponse(success: true, data: data, meta: meta);

  factory ApiResponse.fail(String error, {int? statusCode}) =>
      ApiResponse(success: false, error: error, statusCode: statusCode);
}
