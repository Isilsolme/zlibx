// External download resolution (Anna's Archive + LibGen), modelled on
// OpenlibExtended lib/ui/book_info_page.dart (~150-340).
//
// The download engine itself is NOT reimplemented: once a URL is
// resolved, the existing DownloadNotifier.startDownload(book,
// presetUrl: url) direct-link branch does the work (see
// download_provider.dart). This file only decides WHICH url to hand it,
// and synthesizes the vendor Book the download engine expects.
//
// Resolution order (first route that yields a URL wins):
//   1. LibGen get.php direct link — BookInfoData.mirror already IS the
//      download URL (the key is minted per page load and the link
//      307-redirects to the CDN file; the presetUrl branch follows
//      redirects).
//   2. Anna fast download — the user's own donation key (Hive key
//      'annasDonationKey', entered in Settings) via
//      AnnasArchieve.getFastDownloadUrl. Only attempted when at least
//      one Anna mirror is unprotected: on protected mirrors Dio is
//      dropped outright, so the fast attempt would only burn ~40s of
//      timeouts before falling through.
//   3. Anna slow download, headless WebView — MirrorFetcherService
//      loads the /slow_download/ page and extracts the direct link
//      (the page is a download page, not a file; Dio cannot fetch it
//      past the DDoS-Guard challenge).
//   4. Anna slow download, plain-HTML fallback — Dio GET on the slow
//      page (only works on unprotected mirrors) + extractSlowDownloadLink.
//   5. No route produced a URL — the caller shows 'download_failed'.
//
// The donation key is the user's own Anna's Archive key, stored locally
// in the Hive settings box. It is never logged, never sent anywhere
// except the Anna fast-download endpoint, and never written to any file
// in this repo.

// Dart imports:
import 'dart:async';

// Package imports:
import 'package:dio/dio.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

// Project imports:
import 'package:olib_mobile/core/annas_archive.dart';
import 'package:olib_mobile/services/annas_archieve.dart';
import 'package:olib_mobile/services/download_target.dart';
import 'package:olib_mobile/services/external_logger.dart';
import 'package:olib_mobile/services/hive_service.dart';
import 'package:olib_mobile/services/instance_manager.dart';
import 'package:olib_mobile/services/mirror_fetcher.dart';

/// Hive settings-box key for the user's own Anna's Archive donation key.
const String annasDonationKeyHiveKey = 'annasDonationKey';

/// Reads the stored donation key ('' when none was entered).
String readAnnasDonationKey() {
  final value = HiveService.settingsBox.get(annasDonationKeyHiveKey);
  return value is String ? value.trim() : '';
}

/// Stores the donation key (empty clears it). Never logs the value.
Future<void> saveAnnasDonationKey(String key) async {
  final trimmed = key.trim();
  if (trimmed.isEmpty) {
    await HiveService.settingsBox.delete(annasDonationKeyHiveKey);
  } else {
    await HiveService.settingsBox.put(annasDonationKeyHiveKey, trimmed);
  }
}

/// Stable int id for an external book, derived from its md5.
///
/// The first 8 hex chars parsed as int (the same key the download
/// history uses). NEVER a string's hashCode: Dart string hashes are
/// randomized per run, so download history would stop matching after a
/// restart. Non-hex md5s (LibGen falls back to the edition id or the
/// title when a search row carried no md5 link) fold deterministically
/// over the code units instead — still stable across runs.
int externalBookId(String md5) {
  final hex = md5.length >= 8 ? md5.substring(0, 8) : md5;
  final parsed = int.tryParse(hex, radix: 16);
  if (parsed != null && parsed > 0) return parsed;
  var folded = 0;
  for (final unit in md5.codeUnits) {
    folded = (folded * 31 + unit) & 0x7FFFFFFF;
  }
  return folded == 0 ? 1 : folded;
}

/// Synthesizes the vendor Book the download engine expects, from an
/// external book's detail data (Option A: no DownloadTask rewrite).
/// The id is externalBookId(md5), so download history, the file name
/// and the detail page's progress lookup all key on the same id.
Book synthesizeExternalBook(BookInfoData info) {
  return Book(
    id: externalBookId(info.md5),
    hash: info.md5,
    title: info.title,
    author: info.author,
    cover: info.thumbnail,
    description: info.description,
    publisher: info.publisher,
    extension: (info.format ?? 'epub').toLowerCase(),
  );
}

/// Resolves the download URL for an external book (see the header
/// comment for the fallback order). Never throws: every route failure
/// falls through to the next, and a DownloadTarget without a URL is
/// returned when nothing worked.
Future<DownloadTarget> resolveExternalDownload(BookInfoData info) async {
  final logger = AppLogger();
  final mirror = info.mirror;

  // Route 1 — LibGen get.php is already a direct download URL.
  if (mirror != null &&
      mirror.isNotEmpty &&
      mirror.contains('/get.php?')) {
    return chooseDownloadTarget(url: mirror, fast: true);
  }

  // Route 2 — Anna fast download with the user's donation key, but only
  // when a mirror is reachable by plain Dio (see the header comment).
  final donationKey = readAnnasDonationKey();
  if (donationKey.isNotEmpty) {
    final hasOpen = await InstanceManager()
        .hasUnprotectedMirror(MirrorService.annasArchive);
    if (hasOpen) {
      try {
        final fastLink =
            await AnnasArchieve().getFastDownloadUrl(info.md5, donationKey);
        if (fastLink != null && fastLink.isNotEmpty) {
          return chooseDownloadTarget(url: fastLink, fast: true);
        }
      } catch (e) {
        logger.debug('Fast download lookup failed, falling back to slow',
            tag: 'ExternalDownload');
      }
    }
  }

  // Routes 3-4 — Anna slow download: the mirror is a /slow_download/
  // PAGE, not a file, so its direct link must be extracted.
  if (mirror != null && mirror.isNotEmpty) {
    // Route 3 — headless WebView extraction (works past DDoS-Guard).
    try {
      final mirrors = await MirrorFetcherService().fetchMirrors(mirror);
      if (mirrors.isNotEmpty) {
        return chooseDownloadTarget(url: mirrors.first, fast: false);
      }
    } catch (e) {
      logger.debug('MirrorFetcher slow-link extraction failed, trying '
          'plain-HTML fallback', tag: 'ExternalDownload');
    }

    // Route 4 — plain Dio GET on the slow page (unprotected mirrors
    // only) + HTML parse.
    try {
      final dio = Dio(BaseOptions(headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
            'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 '
            'Safari/537.36',
      }));
      final response =
          await dio.get<String>(mirror).timeout(const Duration(seconds: 15));
      final link = ArchiveParsing.extractSlowDownloadLink(
        response.data ?? '',
        pageUrl: mirror,
      );
      if (link != null && link.isNotEmpty) {
        return chooseDownloadTarget(url: link, fast: false);
      }
    } catch (e) {
      logger.debug('Slow-link HTML fallback failed', tag: 'ExternalDownload');
    }
  }

  // Route 5 — nothing produced a URL.
  return chooseDownloadTarget(url: null, fast: false);
}
