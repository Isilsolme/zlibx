package com.open_library.app

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "zlibx/media_store"
        private const val TAG = "ZlibxMediaStore"
    }

    // File copies (publish to Downloads, copy to cache) can move hundreds
    // of MB; they must not run on the platform (UI) thread or the app
    // freezes / ANRs. A single worker keeps them ordered.
    private val ioExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    // Cheap ContentResolver probes (exists / delete) get their own small
    // pool so they never queue behind a multi-hundred-MB copy.
    private val lightExecutor: ExecutorService = Executors.newFixedThreadPool(2)

    override fun onDestroy() {
        // shutdown() lets a running copy finish; it only rejects new work.
        ioExecutor.shutdown()
        lightExecutor.shutdown()
        super.onDestroy()
    }

    /// Runs [block] on the worker thread and replies on the UI thread.
    private fun <T> runAsync(
        result: MethodChannel.Result,
        executor: ExecutorService = ioExecutor,
        block: () -> T?,
    ) {
        executor.execute {
            val value = try {
                block()
            } catch (e: Exception) {
                Log.w(TAG, "MediaStore task failed", e)
                null
            }
            runOnUiThread {
                try {
                    result.success(value)
                } catch (e: IllegalStateException) {
                    // Engine detached while the copy was running.
                    Log.w(TAG, "reply after detach ignored", e)
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "publishToDownloads" -> {
                        val sourcePath = call.argument<String>("sourcePath")
                        val displayName = call.argument<String>("displayName")
                        val mimeType = call.argument<String>("mimeType")
                        if (sourcePath == null || displayName == null || mimeType == null) {
                            result.success(null)
                        } else {
                            runAsync(result) {
                                publishToDownloads(sourcePath, displayName, mimeType)
                            }
                        }
                    }
                    "contentExists" -> {
                        // openInputStream hits the ContentResolver / disk:
                        // keep it off the platform thread (the history
                        // check calls this once per entry at startup).
                        val uri = call.argument<String>("uri")?.let(Uri::parse)
                        if (uri == null) {
                            result.success(false)
                        } else {
                            runAsync(result, lightExecutor) { contentExists(uri) }
                        }
                    }
                    "openContent" -> {
                        val uri = call.argument<String>("uri")?.let(Uri::parse)
                        result.success(uri != null && openContent(uri))
                    }
                    "deleteContent" -> {
                        val uri = call.argument<String>("uri")?.let(Uri::parse)
                        if (uri == null) {
                            result.success(false)
                        } else {
                            runAsync(result, lightExecutor) { deleteContent(uri) }
                        }
                    }
                    "copyContentToCache" -> {
                        val uri = call.argument<String>("uri")?.let(Uri::parse)
                        if (uri == null) {
                            result.success(null)
                        } else {
                            runAsync(result) { copyContentToCache(uri) }
                        }
                    }
                    "createPendingDownload" -> {
                        val displayName = call.argument<String>("displayName")
                        val mimeType = call.argument<String>("mimeType")
                        if (displayName == null || mimeType == null) {
                            result.success(null)
                        } else {
                            runAsync(result, lightExecutor) {
                                createPendingDownload(displayName, mimeType)
                            }
                        }
                    }
                    "writePendingChunk" -> {
                        val uri = call.argument<String>("uri")?.let(Uri::parse)
                        val bytes = call.argument<ByteArray>("bytes")
                        if (uri == null || bytes == null) {
                            result.success(false)
                        } else {
                            // Runs on the IO worker: a full 256 KB buffer
                            // must never be written on the platform thread.
                            runAsync(result) { writePendingChunk(uri, bytes) }
                        }
                    }
                    "finishPendingDownload" -> {
                        val uri = call.argument<String>("uri")?.let(Uri::parse)
                        if (uri == null) {
                            result.success(false)
                        } else {
                            runAsync(result, lightExecutor) {
                                finishPendingDownload(uri)
                            }
                        }
                    }
                    "abortPendingDownload" -> {
                        val uri = call.argument<String>("uri")?.let(Uri::parse)
                        if (uri == null) {
                            result.success(false)
                        } else {
                            runAsync(result, lightExecutor) {
                                abortPendingDownload(uri)
                            }
                        }
                    }
                    "pendingEntrySize" -> {
                        val uri = call.argument<String>("uri")?.let(Uri::parse)
                        if (uri == null) {
                            result.success(-1L)
                        } else {
                            runAsync(result, lightExecutor) {
                                pendingEntrySize(uri)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// Insert [sourcePath] into the public Downloads/zlibx folder
    /// (MediaStore, Android 10+). Returns the content URI string, or
    /// null when unsupported (pre-Android 10) or on any failure; the
    /// caller keeps the app-specific file in that case.
    private fun publishToDownloads(
        sourcePath: String,
        displayName: String,
        mimeType: String,
    ): String? {
        // RELATIVE_PATH only exists on Android 10+ (API 29).
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val source = File(sourcePath)
        if (!source.exists()) return null
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, displayName)
            put(MediaStore.Downloads.MIME_TYPE, mimeType)
            put(MediaStore.Downloads.RELATIVE_PATH, "Download/zlibx")
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = contentResolver.insert(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            values,
        ) ?: return null
        try {
            val out = contentResolver.openOutputStream(uri)
            if (out == null) {
                contentResolver.delete(uri, null, null)
                return null
            }
            out.use { output ->
                FileInputStream(source).use { input -> input.copyTo(output) }
            }
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
            return uri.toString()
        } catch (e: Exception) {
            Log.w(TAG, "MediaStore publish failed", e)
            try {
                contentResolver.delete(uri, null, null)
            } catch (cleanupError: Exception) {
                // Best-effort cleanup of the half-written entry.
                Log.w(TAG, "MediaStore cleanup failed", cleanupError)
            }
            return null
        }
    }

    /// Insert a pending entry (IS_PENDING=1) into the public
    /// Downloads/zlibx folder (Android 10+). Returns the content URI
    /// string, or null when unsupported (pre-Android 10) or on any
    /// failure. No bytes are written here — the caller streams them
    /// with [writePendingChunk] and publishes with
    /// [finishPendingDownload].
    private fun createPendingDownload(
        displayName: String,
        mimeType: String,
    ): String? {
        // RELATIVE_PATH only exists on Android 10+ (API 29).
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, displayName)
            put(MediaStore.Downloads.MIME_TYPE, mimeType)
            put(MediaStore.Downloads.RELATIVE_PATH, "Download/zlibx")
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        return try {
            contentResolver.insert(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                values,
            )?.toString()
        } catch (e: Exception) {
            Log.w(TAG, "MediaStore pending create failed", e)
            null
        }
    }

    /// Append [bytes] to the pending entry [uri]. Every call opens its
    /// own stream in "wa" (append) mode, writes, and closes — no stream
    /// is held across calls. False on any failure, including devices
    /// that refuse "wa".
    private fun writePendingChunk(uri: Uri, bytes: ByteArray): Boolean {
        return try {
            val out = contentResolver.openOutputStream(uri, "wa")
            if (out == null) {
                Log.w(TAG, "MediaStore pending write: stream unavailable")
                false
            } else {
                out.use { it.write(bytes) }
                true
            }
        } catch (e: Exception) {
            Log.w(TAG, "MediaStore pending write failed", e)
            false
        }
    }

    /// Publish the pending entry by clearing IS_PENDING. False on any
    /// failure (the caller then treats the download as failed and
    /// removes the entry with [abortPendingDownload]).
    private fun finishPendingDownload(uri: Uri): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        return try {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.IS_PENDING, 0)
            }
            contentResolver.update(uri, values, null, null) > 0
        } catch (e: Exception) {
            Log.w(TAG, "MediaStore pending finish failed", e)
            false
        }
    }

    /// Delete a pending entry (cleanup of a cancelled / failed /
    /// superseded download). False on any failure.
    private fun abortPendingDownload(uri: Uri): Boolean {
        return try {
            contentResolver.delete(uri, null, null) > 0
        } catch (e: Exception) {
            Log.w(TAG, "MediaStore pending abort failed", e)
            false
        }
    }

    /// Byte size of the pending entry [uri], read from its file
    /// descriptor (statSize). Used on resume to reconcile the persisted
    /// byte count: if the process died after a chunk was committed but
    /// before the sidecar was written, the sidecar lags the entry and
    /// resuming from it would duplicate bytes. Returns -1 when the size
    /// cannot be determined.
    private fun pendingEntrySize(uri: Uri): Long {
        return try {
            contentResolver.openFileDescriptor(uri, "r")?.use { pfd ->
                pfd.statSize
            } ?: -1L
        } catch (e: Exception) {
            Log.w(TAG, "MediaStore pending size failed", e)
            -1L
        }
    }

    private fun contentExists(uri: Uri): Boolean {
        return try {
            val stream = contentResolver.openInputStream(uri) ?: return false
            stream.close()
            true
        } catch (e: Exception) {
            Log.w(TAG, "MediaStore exists check failed", e)
            false
        }
    }

    private fun openContent(uri: Uri): Boolean {
        val type = contentResolver.getType(uri) ?: "*/*"
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, type)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            startActivity(intent)
            true
        } catch (e: Exception) {
            Log.w(TAG, "MediaStore open failed", e)
            false
        }
    }

    private fun deleteContent(uri: Uri): Boolean {
        return try {
            contentResolver.delete(uri, null, null) > 0
        } catch (e: Exception) {
            Log.w(TAG, "MediaStore delete failed", e)
            false
        }
    }

    /// Delete stale `share_*` temp files from previous shares. Called
    /// before each new copy; only regular files older than 24 hours are
    /// removed, and only the `share_` prefix this class creates — nothing
    /// else in the cache dir is touched. Best-effort: failures are logged
    /// and never fail the copy. Runs on the IO worker (see [runAsync]),
    /// never on the platform thread.
    private fun cleanupStaleShareFiles() {
        val cutoff = System.currentTimeMillis() - 24L * 60L * 60L * 1000L
        val files = try {
            cacheDir.listFiles()
        } catch (e: Exception) {
            Log.w(TAG, "Share cleanup: cannot list cache dir", e)
            return
        } ?: return
        for (file in files) {
            if (!file.isFile) continue
            if (!file.name.startsWith("share_")) continue
            if (file.lastModified() >= cutoff) continue
            try {
                if (!file.delete()) {
                    Log.w(TAG, "Share cleanup: could not delete ${file.name}")
                }
            } catch (e: Exception) {
                Log.w(TAG, "Share cleanup: delete failed", e)
            }
        }
    }

    /// Copy the file behind [uri] into the app cache dir so it can be
    /// handed to share_plus as a plain file path (share_plus cannot
    /// share a content:// URI directly). Returns the temp file's
    /// absolute path, or null on any failure. The temp file keeps
    /// the MediaStore display name when available, with a timestamp
    /// suffix to avoid collisions; it is left in the cache dir for
    /// the OS to reclaim (deleting it right after sharing could
    /// break the receiving app's read).
    private fun copyContentToCache(uri: Uri): String? {
        cleanupStaleShareFiles()
        return try {
            val input = contentResolver.openInputStream(uri) ?: return null
            val displayName = contentResolver.query(
                uri,
                arrayOf(MediaStore.MediaColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
            // Keep CJK and other name characters intact; only strip
            // path separators so the name stays a single segment.
            val safeName = (displayName?.takeIf { it.isNotBlank() }
                ?: uri.lastPathSegment?.takeIf { it.isNotBlank() }
                ?: "shared_file")
                .replace('/', '_')
                .replace('\\', '_')
            val file = File(
                cacheDir,
                "share_${System.currentTimeMillis()}_$safeName",
            )
            input.use { inputStream ->
                file.outputStream().use { output ->
                    inputStream.copyTo(output)
                }
            }
            file.absolutePath
        } catch (e: Exception) {
            Log.w(TAG, "MediaStore copy to cache failed", e)
            null
        }
    }
}
