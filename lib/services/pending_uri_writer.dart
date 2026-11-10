// Pending-URI download writer.
//
// On Android 10+ the download engines can stream bytes directly into a
// MediaStore entry created with IS_PENDING=1, instead of staging the
// book in the app-specific dir and copying it into Downloads/zlibx
// afterwards (saves one full-file copy and the staging space).
//
// This class owns that entry: it buffers chunks, pushes them over the
// platform channel in 256 KB batches (append mode, so a retry must
// resume from exactly the committed byte count), and persists a small
// JSON sidecar (`<savePath>.pending.json`) so an interrupted download
// — user retry or app kill — resumes the same pending entry.
//
// The ResumableDownloader `.meta` validator sidecar is untouched: it
// lives next to the same `.part` path and is removed by [discard] /
// [finish] like a completed staged download would.
//
// Resume safety (B1): the sidecar can lag the entry — if the process
// dies after a chunk was committed but before the sidecar was written,
// resuming from the stale sidecar offset would duplicate bytes. So
// [resume] reconciles against the entry's true size (queried from the
// platform) and treats that as authoritative.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:olib_api_plugin/olib_api_plugin.dart';

import 'media_store.dart';

/// Streams download bytes into a pending MediaStore entry.
///
/// Implements [PendingDownloadWriter] (defined in the vendor plugin)
/// so both download engines — [ResumableDownloader] in this app and
/// `_downloadOnce` inside olib_api_plugin — can write through it
/// without the plugin depending on app code.
class PendingUriWriter implements PendingDownloadWriter {
  PendingUriWriter._({
    required String uri,
    required String savePath,
  })  : _uri = uri,
        _savePath = savePath,
        _statePath = statePathFor(savePath);

  /// JSON sidecar next to the `.part` path. Holds the pending URI and
  /// the committed byte count; written after every successful batch.
  static String statePathFor(String savePath) => '$savePath.pending.json';

  /// Coalesce threshold: chunks are buffered in memory until this
  /// size crosses, so the platform channel (open/write/close a stream
  /// in Kotlin) runs once per 256 KB, not once per network chunk.
  static const int _flushThreshold = 256 * 1024;

  String _uri;
  final String _savePath;
  final String _statePath;

  final List<List<int>> _bufferedChunks = <List<int>>[];
  var _buffered = 0;
  var _committed = 0;
  var _closed = false;

  /// The MediaStore entry currently being filled. Changes when
  /// [reset] recreates the entry after a server-side restart.
  @override
  String get uri => _uri;

  /// Resume offset for the next request: bytes committed to the
  /// pending entry plus bytes still in the buffer.
  @override
  int get bytesWritten => _committed + _buffered;

  /// Bytes actually committed to the MediaStore entry (what the
  /// sidecar persists).
  int get committedBytes => _committed;

  /// Display name derived from the `.part` path (`Title - id.ext.part`
  /// → `Title - id.ext`). Needed to recreate the entry in [reset].
  String get _displayName {
    final base = _savePath.split(Platform.pathSeparator).last;
    return base.endsWith('.part') ? base.substring(0, base.length - 5) : base;
  }

  String get _mimeType => MediaStoreFiles.mimeTypeForExtension(
        _displayName.contains('.') ? _displayName.split('.').last : null,
      );

  /// Create a fresh pending entry. Null when MediaStore cannot create
  /// it (pre-Android 10, or any insert failure) — the caller then
  /// falls back to the staged `.part` flow.
  static Future<PendingUriWriter?> create({
    required String displayName,
    required String mimeType,
    required String savePath,
  }) async {
    final uri = await MediaStoreFiles.createPendingDownload(
      displayName: displayName,
      mimeType: mimeType,
    );
    if (uri == null) return null;
    final writer = PendingUriWriter._(uri: uri, savePath: savePath);
    await writer._persistState();
    return writer;
  }

  /// Resume a previously interrupted pending download from its
  /// sidecar. Returns null when there is no (valid) sidecar. The
  /// caller must still verify the URI with MediaStoreFiles.exists —
  /// the entry may have been removed externally.
  ///
  /// Reconciles the sidecar against the entry's true size: the sidecar
  /// is only written after a chunk commit, so a process killed in
  /// between leaves it lagging. The entry's size is authoritative; when
  /// it differs, it wins and the sidecar is updated. When the size
  /// query fails, the sidecar value is kept.
  static Future<PendingUriWriter?> resume({
    required String savePath,
  }) async {
    final file = File(statePathFor(savePath));
    try {
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final uri = decoded['uri'];
      final bytes = decoded['bytesWritten'];
      if (uri is! String || uri.isEmpty || bytes is! int || bytes < 0) {
        return null;
      }
      final writer = PendingUriWriter._(uri: uri, savePath: savePath);
      writer._committed = bytes;
      final actual = await MediaStoreFiles.pendingEntrySize(uri);
      if (actual >= 0 && actual != writer._committed) {
        writer._committed = actual;
        await writer._persistState();
      }
      return writer;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  /// Buffer one network chunk; flushes automatically once 256 KB
  /// accumulate. A false from the platform channel (storage full,
  /// device refusing "wa", entry gone) throws — the caller aborts.
  @override
  Future<void> add(List<int> chunk) async {
    if (_closed) {
      throw StateError('pending writer is closed');
    }
    _bufferedChunks.add(chunk);
    _buffered += chunk.length;
    if (_buffered >= _flushThreshold) await flush();
  }

  /// Commit all buffered bytes to the pending entry and update the
  /// sidecar. Throws when the platform write fails.
  @override
  Future<void> flush() async {
    if (_buffered == 0) return;
    final combined = Uint8List(_buffered);
    var offset = 0;
    for (final chunk in _bufferedChunks) {
      combined.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    _bufferedChunks.clear();
    _buffered = 0;
    if (!await MediaStoreFiles.writePendingChunk(_uri, combined)) {
      throw StateError(
        'MediaStore pending write failed at $_committed bytes',
      );
    }
    _committed += combined.length;
    await _persistState();
  }

  /// Flush and close; no further [add] / [reset] afterwards.
  Future<void> close() async {
    await flush();
    _closed = true;
  }

  /// Discard the pending entry and all sidecars (user cancel, HTML
  /// rejection, unrecoverable failure). Also removes the `.meta`
  /// validator like a deleted partial would.
  @override
  Future<void> discard() async {
    await MediaStoreFiles.abortPendingDownload(_uri);
    for (final path in <String>[_statePath, '${_savePath}.meta']) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } on FileSystemException {
        // Best-effort cleanup.
      }
    }
  }

  /// Recreate the pending entry empty and point this writer at the
  /// new URI. Required when the server refuses to honour the resume
  /// offset (200 or 416 on a resume request): the old entry cannot be
  /// truncated, only replaced — appending a restarted body would
  /// corrupt the file. False when the new entry cannot be created.
  @override
  Future<bool> reset() async {
    if (_closed) return false;
    await MediaStoreFiles.abortPendingDownload(_uri);
    _bufferedChunks.clear();
    _buffered = 0;
    _committed = 0;
    final fresh = await MediaStoreFiles.createPendingDownload(
      displayName: _displayName,
      mimeType: _mimeType,
    );
    if (fresh == null) return false;
    _uri = fresh;
    await _persistState();
    return true;
  }

  /// Flush the remaining buffer and publish the entry (clear
  /// IS_PENDING). Removes the pending sidecar and the `.meta`
  /// validator on success. False when publishing fails — the caller
  /// treats the download as failed and must not record the URI.
  Future<bool> finish() async {
    await close();
    final published = await MediaStoreFiles.finishPendingDownload(_uri);
    if (!published) return false;
    for (final path in <String>[_statePath, '${_savePath}.meta']) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } on FileSystemException {
        // Best-effort cleanup.
      }
    }
    return true;
  }

  Future<void> _persistState() async {
    try {
      await File(_statePath).writeAsString(
        jsonEncode(<String, Object>{
          'uri': _uri,
          'bytesWritten': _committed,
        }),
      );
    } on FileSystemException {
      // Losing the sidecar only costs a fresh download on retry.
    }
  }
}
