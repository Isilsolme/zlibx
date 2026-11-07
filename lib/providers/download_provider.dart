import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';
import '../services/http_client.dart';
import '../services/media_store.dart';
import '../services/storage_service.dart';
import '../utils/file_utils.dart';
import 'zlibrary_provider.dart';

enum DownloadStatus { pending, downloading, completed, error, cancelled }

class DownloadTask {
  final String id;
  final Book book;
  final double progress;
  final DownloadStatus status;
  final String? filePath;
  final String? error;
  final DateTime? downloadedAt;
  final int? fileSize;
  final bool needsFreshLink;
  final bool missingFile;

  /// 用户自己 Z 站账号当日下载次数已用尽导致的失败。
  final bool quotaExceeded;

  bool get canRetry =>
      (status == DownloadStatus.error || status == DownloadStatus.cancelled) &&
      !needsFreshLink &&
      !missingFile &&
      book.id > 0 &&
      (book.hash?.isNotEmpty ?? false);

  const DownloadTask({
    required this.id,
    required this.book,
    this.progress = 0.0,
    this.status = DownloadStatus.pending,
    this.filePath,
    this.error,
    this.downloadedAt,
    this.fileSize,
    this.needsFreshLink = false,
    this.missingFile = false,
    this.quotaExceeded = false,
  });

  DownloadTask copyWith({
    String? id,
    Book? book,
    double? progress,
    DownloadStatus? status,
    String? filePath,
    String? error,
    DateTime? downloadedAt,
    int? fileSize,
    bool? needsFreshLink,
    bool? missingFile,
    bool? quotaExceeded,
  }) {
    return DownloadTask(
      id: id ?? this.id,
      book: book ?? this.book,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      filePath: filePath ?? this.filePath,
      error: error ?? this.error,
      downloadedAt: downloadedAt ?? this.downloadedAt,
      fileSize: fileSize ?? this.fileSize,
      needsFreshLink: needsFreshLink ?? this.needsFreshLink,
      missingFile: missingFile ?? this.missingFile,
      quotaExceeded: quotaExceeded ?? this.quotaExceeded,
    );
  }
}

/// Z 站当日下载额度已用尽。精简版仓库里此前只有引用、没有定义
///（原定义随私有插件缺失），此处按仓库内同类异常的写法补定义；
/// 用法只有无参构造与类型捕获，不携带额外字段。
class DownloadLimitReachedException implements Exception {
  const DownloadLimitReachedException();
  @override
  String toString() => 'DownloadLimitReachedException';
}

class DownloadNotifier extends StateNotifier<List<DownloadTask>> {
  final ZLibraryApi _api;
  final StorageService _storage;
  final Map<String, CancelToken> _cancelTokens = {};
  late final Future<void> ready;

  DownloadNotifier(this._api, this._storage) : super([]) {
    // Load persisted download history on initialization
    ready = _loadDownloadHistory();
  }

  /// Load completed downloads from storage on app startup
  Future<void> _loadDownloadHistory() async {
    try {
      final history = await _storage.getDownloadHistory();
      final List<DownloadTask> loadedTasks = [];

      for (final entry in history.entries) {
        final bookId = entry.key;
        final data = entry.value as Map<String, dynamic>;

        final filePath = data['filePath'] as String?;

        // Only add if file still exists (content:// URIs from
        // MediaStore publishes are checked through the resolver).
        if (filePath != null) {
          final file = File(filePath);
          final fileExists = await MediaStoreFiles.exists(filePath);

          // Create a minimal Book object from stored data
          final book = Book(
            id: int.tryParse(bookId) ?? 0,
            title: data['title'] as String? ?? 'Unknown',
            author: data['author'] as String?,
            cover: data['cover'] as String?,
            extension: data['extension'] as String?,
          );

          loadedTasks.add(
            DownloadTask(
              id: bookId,
              book: book,
              progress: 1.0,
              status: fileExists
                  ? DownloadStatus.completed
                  : DownloadStatus.error,
              filePath: filePath,
              error: fileExists ? null : 'File not found',
              downloadedAt: DateTime.tryParse(
                data['downloadTime']?.toString() ?? '',
              ),
              // MediaStore content URIs have no local File to measure,
              // so the size stays unknown for history-loaded entries.
              fileSize: fileExists && !MediaStoreFiles.isContentUri(filePath)
                  ? await file.length()
                  : null,
              missingFile: !fileExists,
            ),
          );
        }
      }

      // Update state with loaded tasks
      if (loadedTasks.isNotEmpty) {
        state = loadedTasks;
      }
    } catch (e) {
      // History failure should not break new downloads.
      debugPrint('Could not load download history: ${e.runtimeType}');
    }
  }

  /// 下载保存目录（各平台统一入口，下载与「文件已存在」判断共用）。
  Future<String> _resolveSaveDir() async {
    if (Platform.isAndroid) return (await _androidDownloadDir()).path;

    final customPath = await _storage.getDownloadPath();
    if (customPath != null && customPath.isNotEmpty) {
      final dir = Directory(customPath);
      if (!await dir.exists()) await dir.create(recursive: true);
      return customPath;
    }
    return (await getApplicationDocumentsDirectory()).path;
  }

  /// Android 应用专属外部目录 `<...>/Android/data/<pkg>/files/Olib`。
  ///
  /// 这只是下载的暂存目录：下完后经 MediaStore 发布到公共
  /// `Download/zlibx`，历史记录记的是发布后的 content:// 位置。
  /// 专属目录无需任何存储权限，卸载时随应用一起清除；历史记录里
  /// 的旧路径仍可打开。
  Future<Directory> _androidDownloadDir() async {
    // 形如 /storage/emulated/<user>/Android/data/<pkg>/files
    final appExternal = await getExternalStorageDirectory();
    if (appExternal == null) return getApplicationDocumentsDirectory();

    final dir = Directory('${appExternal.path}/Olib');
    try {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    } on FileSystemException catch (e) {
      debugPrint('App download dir unavailable, fallback: $e');
      return appExternal;
    }
  }

  /// Check if file already exists for a book
  /// Returns the file path if exists, null otherwise
  Future<String?> checkFileExists(Book book) async {
    // First check download history
    final historyPath = await _storage.getDownloadedFilePath(
      book.id.toString(),
    );
    if (historyPath != null) {
      if (await MediaStoreFiles.exists(historyPath)) {
        return historyPath;
      }
    }

    // Also check if file exists in download directory (may have been downloaded elsewhere)
    final savePath = await _buildSavePath(book);
    if (savePath != null) {
      final file = File(savePath);
      if (await file.exists()) {
        return savePath;
      }
    }

    return null;
  }

  /// Build a safe filename for a book
  String _buildSafeFileName(Book book) {
    String safeTitle = book.title
        .replaceAll(RegExp(r'[/\\:*?"<>|\x00-\x1f]'), '')
        .trim();

    if (safeTitle.isEmpty) {
      safeTitle = 'book_${book.id}';
      if (book.author != null && book.author!.isNotEmpty) {
        final safeAuthor = book.author!
            .replaceAll(RegExp(r'[/\\:*?"<>|\x00-\x1f]'), '')
            .trim();
        if (safeAuthor.isNotEmpty) {
          safeTitle = '$safeAuthor - $safeTitle';
        }
      }
    }

    final cleanExtension = (book.extension ?? 'epub')
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .toLowerCase();
    final ext = cleanExtension.isEmpty ? 'epub' : cleanExtension;
    // Android caps a filename at 255 bytes; keep the whole
    // 'title - id.ext' within maxFileNameBytes so a long (e.g.
    // Chinese) title can never fail the write.
    final suffix = ' - ${book.id}.$ext';
    safeTitle = truncateUtf8ByBytes(
      safeTitle,
      maxFileNameBytes - utf8.encode(suffix).length,
    );
    return '$safeTitle$suffix';
  }

  /// Build save path for a book (for non-MediaStore platforms)
  Future<String?> _buildSavePath(Book book) async {
    try {
      final baseDir = await _resolveSaveDir();
      return '$baseDir/${_buildSafeFileName(book)}';
    } catch (e) {
      return null;
    }
  }

  /// Start a download.
  ///
  /// 默认走 ZLibraryApi（用户自己账号查 URL + 下载）。
  /// [presetUrl] 传入时跳过 URL 获取，直接用此 URL 下文件 —
  /// 用于 LAN 传书（电脑直连下载）。
  /// [presetHeaders] 随 presetUrl 请求发送的 header（LAN token 走
  /// `X-Olib-Token`，绝不拼进 URL）。
  Future<void> startDownload(
    Book book, {
    String? presetUrl,
    Map<String, String>? presetHeaders,
  }) async {
    final id = book.id.toString();

    // Check if already downloading
    if (state.any(
      (t) =>
          t.id == id &&
          (t.status == DownloadStatus.downloading ||
              t.status == DownloadStatus.pending),
    )) {
      return;
    }

    // Add or update task to pending
    final cancelToken = CancelToken();
    _cancelTokens[id] = cancelToken;
    _updateOrAddTask(
      DownloadTask(
        id: id,
        book: book,
        status: DownloadStatus.pending,
        needsFreshLink: presetUrl != null,
      ),
    );

    String? temporaryPath;
    try {
      // Downloads go to the app-specific external dir: no storage
      // permission is needed on any Android version.
      final finalPath =
          '${await _resolveSaveDir()}/${_buildSafeFileName(book)}';

      if (cancelToken.isCancelled) return;

      temporaryPath = '$finalPath.part';

      // Update to downloading
      _updateTask(
        id,
        (t) => t.copyWith(status: DownloadStatus.downloading, progress: 0.0),
      );

      // Write to a task-specific temporary file so cancellation never leaves
      // a partial book under its final name.
      final alreadyExists = await File(finalPath).exists();
      if (!alreadyExists && presetUrl != null) {
        // presetUrl 路径（LAN 传书 / 外部源解析链接）：直接 stream 到本地
        // 用独立 Dio，不带 z站 cookie / auth；LAN token 走 header。
        // followRedirects 必须为 true：LibGen get.php 307 跳到 CDN 文件，
        // 不跟随会把重定向响应本身存成文件。LAN 不发重定向，不受影响；
        // 外部下载不带 presetHeaders，不存在 token 外泄问题。
        // receiveTimeout: null = 不限接收超时：大文件慢速网络不能被打断。
        final dio = createDio(receiveTimeout: null);
        await _downloadResumable(
          dio,
          presetUrl,
          temporaryPath,
          headers: presetHeaders,
          onProgress: (received, total) {
            if (total != -1) {
              final progress = received / total;
              _updateTask(id, (t) => t.copyWith(progress: progress));
            }
          },
          cancelToken: cancelToken,
        );
      } else if (!alreadyExists) {
        // 默认路径：用户自己 z站 账号查 URL + 下载
        try {
          await _api.downloadBook(
            book.id.toString(),
            book.hash ?? '',
            temporaryPath,
            onProgress: (received, total) {
              if (total != -1) {
                final progress = received / total;
                _updateTask(id, (t) => t.copyWith(progress: progress));
              }
            },
            cancelToken: cancelToken,
            title: book.title,
          );
        } on DownloadLimitReachedException {
          rethrow;
        } catch (e) {
          // Z 站额度用尽的返回形态不稳定，失败后再查一次资料兜底识别
          if (!cancelToken.isCancelled && await _isOwnQuotaExhausted()) {
            throw DownloadLimitReachedException();
          }
          rethrow;
        }
      }

      if (cancelToken.isCancelled) return;
      if (identical(_cancelTokens[id], cancelToken)) _cancelTokens.remove(id);

      if (await File(temporaryPath).exists()) {
        await File(temporaryPath).rename(finalPath);
      }

      final completedAt = DateTime.now();
      final fileSize = await File(finalPath).length();

      // Publish into the public Downloads/zlibx folder (MediaStore,
      // Android 10+). On failure keep the app-specific file and report
      // success with that location — the download itself still counts.
      var recordedPath = finalPath;
      if (Platform.isAndroid) {
        final uri = await MediaStoreFiles.publishToDownloads(
          sourcePath: finalPath,
          displayName: _buildSafeFileName(book),
          mimeType: MediaStoreFiles.mimeTypeForExtension(book.extension),
        );
        if (uri != null) {
          recordedPath = uri;
          try {
            await File(finalPath).delete();
          } catch (e) {
            debugPrint('Could not remove staged download: $e');
          }
        } else {
          debugPrint(
            'MediaStore publish failed, keeping app-specific file',
          );
        }
      }

      // Save to download history (with cover and extension for persistence)
      await _storage.addToDownloadHistory(
        book.id.toString(),
        book.title,
        book.author,
        recordedPath,
        cover: book.cover,
        extension: book.extension,
      );
      _updateTask(
        id,
        (t) => t.copyWith(
          status: DownloadStatus.completed,
          progress: 1.0,
          filePath: recordedPath,
          downloadedAt: completedAt,
          fileSize: fileSize,
        ),
      );
    } on DownloadLimitReachedException catch (e) {
      if (!cancelToken.isCancelled) {
        _updateTask(
          id,
          (t) => t.copyWith(
            status: DownloadStatus.error,
            error: e.toString(),
            quotaExceeded: true,
          ),
        );
      }
    } catch (e) {
      if (!cancelToken.isCancelled) {
        _updateTask(
          id,
          (t) => t.copyWith(status: DownloadStatus.error, error: e.toString()),
        );
      }
    } finally {
      // Keep the partial file after a failure so the next retry resumes
      // from it instead of starting over; only an explicit user cancel
      // drops it. On success the file was already renamed away.
      if (temporaryPath != null && cancelToken.isCancelled) {
        final partial = File(temporaryPath);
        try {
          if (await partial.exists()) await partial.delete();
        } catch (error) {
          debugPrint('Could not remove partial download: ${error.runtimeType}');
        }
      }
      if (identical(_cancelTokens[id], cancelToken)) _cancelTokens.remove(id);
    }
  }

  /// Download [url] to [savePath], resuming from the bytes already on
  /// disk when the server honours Range. A 200 restarts the file from
  /// zero; a 206 appends; a 416 truncates and restarts once. Progress
  /// reports the true position against the full size. Redirects are
  /// followed by Dio (no auth headers travel on this path).
  Future<void> _downloadResumable(
    Dio dio,
    String url,
    String savePath, {
    Map<String, String>? headers,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final file = File(savePath);
    final start = await file.exists() ? await file.length() : 0;
    final reqHeaders = <String, String>{...?headers};
    if (start > 0) reqHeaders['Range'] = 'bytes=$start-';
    final res = await dio.get<ResponseBody>(
      url,
      options: Options(
        headers: reqHeaders,
        responseType: ResponseType.stream,
        followRedirects: true,
        // 416 is allowed through so the handler below can truncate and
        // restart; anything else outside 2xx still throws.
        validateStatus: (status) =>
            status != null &&
            ((status >= 200 && status < 300) || status == 416),
      ),
      cancelToken: cancelToken,
    );
    final code = res.statusCode ?? 0;
    if (code == 416 && start > 0) {
      await file.writeAsBytes(const []);
      return _downloadResumable(
        dio,
        url,
        savePath,
        headers: headers,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    }
    final contentLength = int.tryParse(
          res.headers.value(HttpHeaders.contentLengthHeader) ?? '',
        ) ??
        -1;
    final resumed = code == 206 && start > 0;
    final total = resumed ? start + contentLength : contentLength;
    final sink = file.openWrite(mode: resumed ? FileMode.append : FileMode.write);
    var received = resumed ? start : 0;
    try {
      await for (final chunk in res.data!.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } finally {
      await sink.close();
    }
  }

  Future<bool> _isOwnQuotaExhausted() async {
    try {
      final profile = await _api.getProfile();
      return profile.success &&
          profile.data != null &&
          profile.data!.downloadsLeft != null &&
          profile.data!.downloadsLeft! <= 0;
    } catch (e) {
      debugPrint('Could not check download quota: ${e.runtimeType}');
      return false;
    }
  }

  /// Cancel a download
  void cancelDownload(String id) {
    final token = _cancelTokens[id];
    if (token == null) return;
    token.cancel();
    _updateTask(id, (t) => t.copyWith(status: DownloadStatus.cancelled));
  }

  void markMissingFile(String id) {
    _updateTask(
      id,
      (task) => task.copyWith(
        status: DownloadStatus.error,
        missingFile: true,
        error: 'File not found',
      ),
    );
  }

  /// Remove task and delete file
  Future<void> removeTask(String id) async {
    cancelDownload(id);
    final task = state.firstWhere(
      (t) => t.id == id,
      orElse: () => throw Exception("Task not found"),
    );

    // Delete file if exists (content:// URIs via ContentResolver).
    if (task.filePath != null) {
      await MediaStoreFiles.delete(task.filePath!);
    }

    // Remove from persistent storage
    await _storage.removeFromDownloadHistory(id);

    // Remove from state
    state = state.where((t) => t.id != id).toList();
  }

  void _updateOrAddTask(DownloadTask task) {
    if (state.any((t) => t.id == task.id)) {
      state = state.map((t) => t.id == task.id ? task : t).toList();
    } else {
      state = [...state, task];
    }
  }

  void _updateTask(String id, DownloadTask Function(DownloadTask) updater) {
    state = state.map((t) {
      if (t.id == id) {
        return updater(t);
      }
      return t;
    }).toList();
  }
}

final downloadProvider =
    StateNotifierProvider<DownloadNotifier, List<DownloadTask>>((ref) {
      final api = ref.watch(zlibraryApiProvider);
      final storage = ref.watch(storageServiceProvider);
      return DownloadNotifier(api, storage);
    });
