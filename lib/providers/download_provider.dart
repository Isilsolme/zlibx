import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';
import '../services/http_client.dart';
import '../services/media_store.dart';
import '../services/pending_uri_writer.dart';
import '../services/resumable_downloader.dart';
import '../services/storage_service.dart';
import '../utils/diagnostics.dart';
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

class DownloadNotifier extends Notifier<List<DownloadTask>> {
  // Getters, not `late final` fields: ref.invalidate (account switch,
  // line change, logout) re-runs build() on the SAME notifier instance,
  // and a second assignment to a late final throws LateInitializationError
  // — the same trap that blanked the library screen in SavedBooksNotifier.
  ZLibraryApi get _api => ref.read(zlibraryApiProvider);
  StorageService get _storage => ref.read(storageServiceProvider);
  final Map<String, CancelToken> _cancelTokens = {};

  /// Throttle for progress ticks: Dio can fire dozens of callbacks per
  /// second, and every publish rebuilds the whole task list for every
  /// listener. A tick is published only when progress moved >= 1% or
  /// >= 200 ms passed since the last publish for that task. Terminal
  /// transitions (completed / error / cancelled) never go through here,
  /// so they are always published immediately.
  final Map<String, double> _lastPublishedProgress = {};
  final Map<String, DateTime> _lastPublishedAt = {};

  // Not final: build() re-assigns it on every invalidate (nothing reads
  // it today; kept for the startup-history signal).
  late Future<void> ready;

  @override
  List<DownloadTask> build() {
    // Load persisted download history on initialization
    ready = _loadDownloadHistory();
    return [];
  }

  /// Load completed downloads from storage on app startup
  Future<void> _loadDownloadHistory() async {
    try {
      final history = await _storage.getDownloadHistory();
      // Entries are independent, so they load in parallel; Future.wait
      // keeps the result order, so the task order matches the old
      // serial loop exactly.
      // Bounded batches: every entry costs a MediaStore platform-channel
      // call, and an unbounded fan-out over a long history floods the
      // channel and the IO worker at startup. Order is preserved.
      const batchSize = 8;
      final entries = history.entries.toList();
      final tasks = <DownloadTask?>[];
      for (var i = 0; i < entries.length; i += batchSize) {
        final batch = entries.skip(i).take(batchSize);
        tasks.addAll(
          await Future.wait(
            batch.map(
              (entry) => _taskFromHistoryEntry(
                entry.key,
                entry.value as Map<String, dynamic>,
              ),
            ),
          ),
        );
      }
      final loadedTasks = [for (final task in tasks) if (task != null) task];

      // Merge by id instead of overwriting: the user may already have
      // started a new download while this async history load was in
      // flight — `state = loadedTasks` would erase it and its progress
      // bar would silently disappear (the download keeps running but
      // _updateTask can no longer find the row).
      if (loadedTasks.isNotEmpty) {
        final loadedIds = loadedTasks.map((t) => t.id).toSet();
        state = [
          ...state.where((t) => !loadedIds.contains(t.id)),
          ...loadedTasks,
        ];
      }
    } catch (e) {
      // History failure should not break new downloads.
      debugPrint('Could not load download history: ${e.runtimeType}');
    }
  }

  /// Builds one history task from its stored entry, or null when the
  /// entry has no file path. Kept separate so [_loadDownloadHistory]
  /// can load entries in parallel with [Future.wait]; within one entry
  /// the order is unchanged (existence is checked before measuring the
  /// file, and the length is only measured for a non-content URI that
  /// exists).
  Future<DownloadTask?> _taskFromHistoryEntry(
    String bookId,
    Map<String, dynamic> data,
  ) async {
    final filePath = data['filePath'] as String?;
    if (filePath == null) return null;
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

    return DownloadTask(
      id: bookId,
      book: book,
      progress: 1.0,
      status: fileExists ? DownloadStatus.completed : DownloadStatus.error,
      filePath: filePath,
      error: fileExists ? null : 'File not found',
      downloadedAt: DateTime.tryParse(data['downloadTime']?.toString() ?? ''),
      // MediaStore content URIs have no local File to measure,
      // so the size stays unknown for history-loaded entries.
      fileSize: fileExists && !MediaStoreFiles.isContentUri(filePath)
          ? await file.length()
          : null,
      missingFile: !fileExists,
    );
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
    // The history lookup and the save-path build do not depend on each
    // other, so they run together; existence is then checked in the
    // same priority order as before (history first, then save path).
    final results = await Future.wait([
      _storage.getDownloadedFilePath(book.id.toString()),
      _buildSavePath(book),
    ]);
    final historyPath = results[0];
    final savePath = results[1];
    if (historyPath != null &&
        await MediaStoreFiles.exists(historyPath)) {
      return historyPath;
    }

    // Also check if file exists in download directory (may have been downloaded elsewhere)
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
    // Pending MediaStore entry for this download (Android 10+ only).
    // Null = staging fallback (.part file + publish copy).
    PendingUriWriter? pendingWriter;
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
      // Pending MediaStore entry (Android 10+): only when actually
      // downloading. An already-present file needs no writer — creating
      // one would publish an empty entry and record its URI instead of
      // the real file. Any failure here keeps the staging flow
      // (pendingWriter stays null).
      if (Platform.isAndroid && !alreadyExists) {
        pendingWriter = await PendingUriWriter.resume(
          savePath: temporaryPath,
        );
        if (pendingWriter != null &&
            !await MediaStoreFiles.exists(pendingWriter.uri)) {
          // The pending entry vanished (user deleted it in Files);
          // the sidecar is stale — drop it and start a fresh entry.
          await pendingWriter.discard();
          pendingWriter = null;
        }
        pendingWriter ??= await PendingUriWriter.create(
          displayName: _buildSafeFileName(book),
          mimeType: MediaStoreFiles.mimeTypeForExtension(book.extension),
          savePath: temporaryPath,
        );
      }
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
            // `total` can be 0 (empty body / CDN without length): only a
            // positive total yields a valid fraction — 0/0 would push a
            // NaN into the state and straight into the progress bar.
            if (total > 0) {
              final progress = received / total;
              _updateProgress(id, progress);
            }
          },
          cancelToken: cancelToken,
          pendingWriter: pendingWriter,
        );
      } else if (!alreadyExists) {
        // 默认路径：用户自己 z站 账号查 URL + 下载
        try {
          await _api.downloadBook(
            book.id.toString(),
            book.hash ?? '',
            temporaryPath,
            onProgress: (received, total) {
              // Same NaN guard as the preset branch above.
              if (total > 0) {
                final progress = received / total;
                _updateProgress(id, progress);
              }
            },
            cancelToken: cancelToken,
            title: book.title,
            pendingWriter: pendingWriter,
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

      final completedAt = DateTime.now();
      int fileSize;

      // The final location, and where the history records it.
      var recordedPath = finalPath;
      if (pendingWriter != null) {
        // Flush the writer's buffer and publish the pending entry
        // (clear IS_PENDING): the book is already in Downloads/zlibx.
        await pendingWriter.flush();
        if (!await pendingWriter.finish()) {
          // Publishing failed (e.g. the entry was removed): the book
          // never reached Downloads — fail, don't record a dead URI.
          await pendingWriter.discard();
          pendingWriter = null;
          throw StateError(
            'could not publish the download into Downloads/zlibx',
          );
        }
        recordedPath = pendingWriter.uri;
        // After flush() the buffer is empty, so bytesWritten is the
        // total committed size — the file size for the task record.
        fileSize = pendingWriter.bytesWritten;
        pendingWriter = null;
      } else {
        if (await File(temporaryPath).exists()) {
          await File(temporaryPath).rename(finalPath);
        }
        fileSize = await File(finalPath).length();

        // Publish into the public Downloads/zlibx folder (MediaStore,
        // Android 10+). On failure keep the app-specific file and
        // report success with that location — the download itself
        // still counts.
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
      _clearProgressThrottle(id);
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
        _clearProgressThrottle(id);
      }
    } catch (e) {
      // HTML rejection — typed by both engines (DownloadContentException
      // from ResumableDownloader, DownloadHtmlException from the vendor
      // plugin): the destination is useless, never resume it. The
      // publish failure above already discarded before throwing.
      if (e is DownloadContentException || e is DownloadHtmlException) {
        if (pendingWriter != null) {
          await pendingWriter.discard();
          pendingWriter = null;
        }
      }
      if (!cancelToken.isCancelled) {
        _updateTask(
          id,
          (t) => t.copyWith(status: DownloadStatus.error, error: e.toString()),
        );
        _clearProgressThrottle(id);
      }
    } finally {
      // Keep the partial file after a failure so the next retry resumes
      // from it instead of starting over; only an explicit user cancel
      // drops it. On success the file was already renamed away.
      if (temporaryPath != null && cancelToken.isCancelled) {
        if (pendingWriter != null) {
          await pendingWriter.discard();
          pendingWriter = null;
        } else {
          await _deletePartial(temporaryPath);
        }
      }
      if (identical(_cancelTokens[id], cancelToken)) _cancelTokens.remove(id);
    }
  }

  /// Download [url] to [savePath] through [ResumableDownloader]: resume
  /// with `Range` + `If-Range`, reject HTML answers, flag truncated
  /// streams. Redirects are followed by Dio (no auth headers travel on
  /// this path).
  Future<void> _downloadResumable(
    Dio dio,
    String url,
    String savePath, {
    Map<String, String>? headers,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
    PendingDownloadWriter? pendingWriter,
  }) async {
    try {
      await ResumableDownloader.download(
        dio,
        url,
        savePath,
        headers: headers,
        onProgress: onProgress,
        cancelToken: cancelToken,
        pendingWriter: pendingWriter,
      );
    } on DownloadContentException {
      // Not a book: the partial (if any) is useless, never resume it.
      if (pendingWriter != null) {
        await pendingWriter.discard();
      } else {
        await _deletePartial(savePath);
      }
      rethrow;
    }
  }

  Future<void> _deletePartial(String partPath) async {
    for (final path in [partPath, ResumableDownloader.metaPathFor(partPath)]) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (error) {
        logIgnored('download_partial', error);
      }
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
    _clearProgressThrottle(id);
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
    // Idempotent delete: the task may already be gone (double tap on the
    // menu, history cleanup racing the UI). A missing task used to throw
    // and the caller showed "删除失败" for a perfectly successful delete.
    final matches = state.where((t) => t.id == id).toList();
    if (matches.isEmpty) return;
    final task = matches.first;

    // Delete file if exists (content:// URIs via ContentResolver).
    if (task.filePath != null) {
      await MediaStoreFiles.delete(task.filePath!);
    }

    // Remove from persistent storage
    await _storage.removeFromDownloadHistory(id);

    // Remove from state
    state = state.where((t) => t.id != id).toList();
    _clearProgressThrottle(id);
  }

  void _updateOrAddTask(DownloadTask task) {
    if (state.any((t) => t.id == task.id)) {
      state = state.map((t) => t.id == task.id ? task : t).toList();
    } else {
      state = [...state, task];
    }
  }

  /// Publishes one progress tick, throttled: a tick below 1.0 is only
  /// published when progress moved >= 1% since the last publish for
  /// this task, or >= 200 ms passed. A tick that reaches 1.0 always
  /// goes through immediately.
  void _updateProgress(String id, double progress) {
    // Late ticks from a cancelled/finished download must not republish
    // state: cancelDownload already flipped the status and cleared the
    // throttle maps, but chunks already queued in the stream keep
    // arriving for a moment.
    final token = _cancelTokens[id];
    if (token == null || token.isCancelled) return;
    // No firstOrNull dependency: avoid pulling in package:collection.
    DownloadTask? task;
    for (final t in state) {
      if (t.id == id) {
        task = t;
        break;
      }
    }
    if (task == null ||
        (task.status != DownloadStatus.downloading &&
            task.status != DownloadStatus.pending)) {
      return;
    }
    if (progress < 1.0) {
      final now = DateTime.now();
      final last = _lastPublishedProgress[id];
      final lastAt = _lastPublishedAt[id];
      if (last != null &&
          (progress - last).abs() < 0.01 &&
          lastAt != null &&
          now.difference(lastAt).inMilliseconds < 200) {
        return;
      }
      _lastPublishedProgress[id] = progress;
      _lastPublishedAt[id] = now;
    }
    _updateTask(id, (t) => t.copyWith(progress: progress));
  }

  /// Drops the throttle bookkeeping for [id]; called when a task leaves
  /// the downloading state so the maps stay bounded.
  void _clearProgressThrottle(String id) {
    _lastPublishedProgress.remove(id);
    _lastPublishedAt.remove(id);
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
    NotifierProvider<DownloadNotifier, List<DownloadTask>>(
      DownloadNotifier.new,
    );

/// One download task by id. Watching this instead of [downloadProvider]
/// rebuilds a widget only when ITS task changes: [_updateTask] keeps the
/// identity of every untouched task, so `select` sees no change for them.
/// Use it in per-book widgets (action bars, list tiles) so one progress
/// tick no longer rebuilds every listener of the whole list.
final downloadTaskProvider =
    Provider.autoDispose.family<DownloadTask?, String>((ref, id) {
  return ref.watch(
    downloadProvider.select((tasks) {
      for (final t in tasks) {
        if (t.id == id) return t;
      }
      return null;
    }),
  );
});

/// Task ids per downloads tab, in display order, with value equality:
/// two structures are equal when both id lists match element-wise.
/// Progress ticks change neither list, so a screen watching this
/// rebuilds only when a task is added/removed, changes status (and so
/// moves tabs), or completes (changing the completed order).
class DownloadListStructure {
  const DownloadListStructure({
    required this.ongoingIds,
    required this.completedIds,
  });

  final List<String> ongoingIds;
  final List<String> completedIds;

  @override
  bool operator ==(Object other) =>
      other is DownloadListStructure &&
      _idsEqual(ongoingIds, other.ongoingIds) &&
      _idsEqual(completedIds, other.completedIds);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(ongoingIds), Object.hashAll(completedIds));
}

bool _idsEqual(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Display order within the downloads tabs (same sort the screen used
/// to do inline: ongoing by status priority, completed newest first).
int _downloadPriority(DownloadStatus status) => switch (status) {
  DownloadStatus.downloading => 0,
  DownloadStatus.pending => 1,
  DownloadStatus.error => 2,
  DownloadStatus.cancelled => 3,
  DownloadStatus.completed => 4,
};

/// The downloads list structure (ids per tab, in display order).
/// Watch this in the list screen instead of [downloadProvider]: the
/// structure only changes when the set of tasks or their statuses
/// change, so progress ticks do not rebuild the screen. Each row then
/// watches [downloadTaskProvider] for its own live task.
final downloadListStructureProvider = Provider<DownloadListStructure>((ref) {
  return ref.watch(
    downloadProvider.select((tasks) {
      final ongoing = tasks
          .where((task) => task.status != DownloadStatus.completed)
          .toList()
        ..sort(
          (a, b) => _downloadPriority(
            a.status,
          ).compareTo(_downloadPriority(b.status)),
        );
      final completed = tasks
          .where((task) => task.status == DownloadStatus.completed)
          .toList()
        ..sort(
          (a, b) => (b.downloadedAt ?? DateTime(0)).compareTo(
            a.downloadedAt ?? DateTime(0),
          ),
        );
      return DownloadListStructure(
        ongoingIds: ongoing.map((task) => task.id).toList(),
        completedIds: completed.map((task) => task.id).toList(),
      );
    }),
  );
});
