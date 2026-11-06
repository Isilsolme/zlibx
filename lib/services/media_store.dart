// MediaStore bridge: publish finished downloads into the public
// Downloads/zlibx folder (Android 10+), and handle the content://
// locations that come back from it (open / exists / delete / share).
//
// The download engine still writes to the app-specific dir first;
// DownloadNotifier publishes the finished file and records the
// content URI. Old history entries keep plain file paths and keep
// working — every helper below routes on the `content://` prefix.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';

class MediaStoreFiles {
  static const _channel = MethodChannel('zlibx/media_store');

  static bool isContentUri(String location) =>
      location.startsWith('content://');

  /// MIME type for a book extension (used for the MediaStore insert).
  static String mimeTypeForExtension(String? extension) {
    switch ((extension ?? '').toLowerCase()) {
      case 'epub':
        return 'application/epub+zip';
      case 'pdf':
        return 'application/pdf';
      case 'mobi':
        return 'application/x-mobipocket-ebook';
      case 'azw3':
        return 'application/vnd.amazon.ebook';
      case 'azw':
        return 'application/vnd.amazon.mobi8-ebook';
      case 'fb2':
        return 'application/x-fictionbook+xml';
      case 'cbz':
        return 'application/x-cbz';
      case 'cbr':
        return 'application/x-cbr';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  /// Copy [sourcePath] into the public Downloads/zlibx folder via
  /// MediaStore (Android 10+ only). Returns the content URI string,
  /// or null when MediaStore is unavailable or the publish fails —
  /// the caller then keeps the app-specific file and reports success
  /// with that location.
  static Future<String?> publishToDownloads({
    required String sourcePath,
    required String displayName,
    required String mimeType,
  }) async {
    if (!Platform.isAndroid) return null;
    try {
      final uri = await _channel.invokeMethod<String>(
        'publishToDownloads',
        <String, Object>{
          'sourcePath': sourcePath,
          'displayName': displayName,
          'mimeType': mimeType,
        },
      );
      return (uri != null && uri.isNotEmpty) ? uri : null;
    } on PlatformException catch (e) {
      debugPrint('MediaStore publish failed: ${e.code} ${e.message}');
      return null;
    }
  }

  /// Existence check that understands both plain paths and the
  /// content:// URIs publishToDownloads returns.
  static Future<bool> exists(String location) async {
    if (isContentUri(location)) {
      if (!Platform.isAndroid) return false;
      try {
        return await _channel.invokeMethod<bool>(
              'contentExists',
              <String, Object>{'uri': location},
            ) ??
            false;
      } on PlatformException {
        return false;
      }
    }
    return File(location).exists();
  }

  /// Open with the system default app. Content URIs go through the
  /// platform channel (ACTION_VIEW with a read grant); plain paths
  /// keep using OpenFilex as before.
  static Future<bool> open(String location) async {
    if (isContentUri(location)) {
      if (!Platform.isAndroid) return false;
      try {
        return await _channel.invokeMethod<bool>(
              'openContent',
              <String, Object>{'uri': location},
            ) ??
            false;
      } on PlatformException {
        return false;
      }
    }
    final result = await OpenFilex.open(location);
    return result.type == ResultType.done;
  }

  /// Delete. Content URIs go through ContentResolver; plain paths
  /// are deleted as files, as before.
  static Future<bool> delete(String location) async {
    if (isContentUri(location)) {
      if (!Platform.isAndroid) return false;
      try {
        return await _channel.invokeMethod<bool>(
              'deleteContent',
              <String, Object>{'uri': location},
            ) ??
            false;
      } on PlatformException {
        return false;
      }
    }
    final file = File(location);
    if (await file.exists()) {
      await file.delete();
      return true;
    }
    return false;
  }

  /// Resolve a location to a plain file path share_plus can hand to
  /// the system share sheet. Plain paths pass through unchanged;
  /// content:// URIs are copied to a temp file in the app cache dir
  /// first (share_plus cannot share a content URI directly).
  /// Returns null when the temp copy fails.
  static Future<String?> shareablePath(String location) async {
    if (!isContentUri(location)) return location;
    if (!Platform.isAndroid) return null;
    try {
      final path = await _channel.invokeMethod<String>(
        'copyContentToCache',
        <String, Object>{'uri': location},
      );
      return (path != null && path.isNotEmpty) ? path : null;
    } on PlatformException {
      return null;
    }
  }
}
