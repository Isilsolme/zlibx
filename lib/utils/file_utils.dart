import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:android_intent_plus/android_intent.dart';

import '../services/media_store.dart';

/// Check if platform supports opening folder in file manager
/// (Android-only build: always true on Android.)
bool get canOpenFolder => Platform.isAndroid;

/// Open the download folder in the system file manager
Future<bool> openDownloadFolder() async {
  try {
    if (Platform.isAndroid) {
      // Use Intent to open the Downloads folder in the system file manager
      try {
        final intent = AndroidIntent(
          action: 'android.intent.action.VIEW',
          data: 'content://com.android.externalstorage.documents/document/primary%3ADownload%2Fzlibx',
          type: 'vnd.android.document/directory',
          flags: <int>[0x10000000], // FLAG_ACTIVITY_NEW_TASK
        );
        await intent.launch();
        return true;
      } catch (error) {
        debugPrint('[file_utils] ignored ${error.runtimeType}');
        // Fallback: try to open the general Downloads folder
        try {
          final intent = AndroidIntent(
            action: 'android.intent.action.VIEW',
            data: 'content://com.android.externalstorage.documents/root/primary%3ADownload',
            type: 'vnd.android.document/root',
            flags: <int>[0x10000000],
          );
          await intent.launch();
          return true;
        } catch (error) {
          debugPrint('[file_utils] ignored ${error.runtimeType}');
          // Last fallback: open the system file manager app
          try {
            final intent = AndroidIntent(
              action: 'android.intent.action.MAIN',
              category: 'android.intent.category.APP_FILES',
              flags: <int>[0x10000000],
            );
            await intent.launch();
            return true;
          } catch (error) {
            debugPrint('[file_utils] ignored ${error.runtimeType}');
            return false;
          }
        }
      }
    }
    return false;
  } catch (e) {
    debugPrint('Failed to open download folder: $e');
    return false;
  }
}

/// Open a file with the system default application.
/// Understands both plain paths and the content:// URIs of
/// MediaStore-published downloads.
Future<bool> openFile(String filePath) async {
  try {
    if (!await MediaStoreFiles.exists(filePath)) {
      return false;
    }
    return await MediaStoreFiles.open(filePath);
  } catch (e) {
    debugPrint('Failed to open file: $e');
    return false;
  }
}

/// Get file size as human-readable string
String formatFileSize(int bytes) {
  if (bytes > 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  } else if (bytes > 1024) {
    return '${(bytes / 1024).toStringAsFixed(2)} KB';
  } else {
    return '$bytes B';
  }
}

/// Build a safe filename for saving files
String buildSafeFileName(String name, {String? extension}) {
  String safeName = name.replaceAll(RegExp(r'[/\\:*?"<>|\x00-\x1f]'), '').trim();
  if (safeName.isEmpty) {
    safeName = 'file_${DateTime.now().millisecondsSinceEpoch}';
  }
  if (extension != null && extension.isNotEmpty) {
    return '$safeName.$extension';
  }
  return safeName;
}
