// Ported from warreth/OpenlibExtended (AGPL-3.0) — Anna's Archive / LibGen
// book sources. Original file: lib/services/mirror_fetcher.dart
// zlibx is AGPL-3.0 (see LICENSE); upstream MIT attribution for
// shiyi-0x7f/olib-mobile is preserved in LICENSE.
//
// Android-only adaptation: upstream's Linux early-return
// (`PlatformUtils.isLinux` → return []) is deleted — zlibx builds
// Android only and never takes that branch.

// Dart imports:
import 'dart:async';

// Package imports:
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

// Project imports:
import 'package:zlibx/services/external_logger.dart';

/// Service to fetch mirror links in the background without showing UI
class MirrorFetcherService {
  static final MirrorFetcherService _instance = MirrorFetcherService._internal();
  factory MirrorFetcherService() => _instance;
  MirrorFetcherService._internal();

  final AppLogger _logger = AppLogger();

  /// Fetch mirror links from the given URL in the background
  /// Returns a list of mirror download links
  Future<List<String>> fetchMirrors(String url) async {
    _logger.info('Starting background mirror fetch', tag: 'MirrorFetcher', metadata: {'url': url});

    final Completer<List<String>> completer = Completer<List<String>>();
    final List<String> bookDownloadLinks = [];

    HeadlessInAppWebView? headlessWebView;
    try {
      // Create a headless webview to load the page
      final webView = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        onLoadStop: (controller, url) async {
          if (url == null) {
            _logger.warning('URL is null in onLoadStop', tag: 'MirrorFetcher');
            if (!completer.isCompleted) {
              completer.complete([]);
            }
            return;
          }

          _logger.debug('Page loaded successfully', tag: 'MirrorFetcher', metadata: {'url': url.toString()});

          try {
            if (url.toString().contains("slow_download")) {
              // For slow_download pages, extract the direct link
              String query =
                  """var paragraphTag=document.querySelector('p[class="mb-4 text-xl font-bold"]');var anchorTagHref=paragraphTag.querySelector('a').href;var url=()=>{return anchorTagHref};url();""";
              String? mirrorLink = await controller.evaluateJavascript(source: query);
              if (mirrorLink != null) {
                bookDownloadLinks.add(mirrorLink);
                _logger.info('Extracted slow_download link', tag: 'MirrorFetcher');
              }
            } else {
              // For other mirror pages, extract all IPFS/mirror links
              String query =
                  """Array.from(document.querySelectorAll('ul>li>a')).map(e=>e.href).filter(Boolean);""";
              List<dynamic> mirrorLinks =
                  await controller.evaluateJavascript(source: query);
              bookDownloadLinks.addAll(mirrorLinks.cast<String>());
              _logger.info('Extracted mirror links', tag: 'MirrorFetcher', metadata: {'count': bookDownloadLinks.length});
            }

            // Complete the future with the extracted links
            if (!completer.isCompleted) {
              completer.complete(bookDownloadLinks);
            }
          } catch (e) {
            _logger.error('JavaScript evaluation error', tag: 'MirrorFetcher', error: e);
            // Evaluation error, complete with empty list
            if (!completer.isCompleted) {
              completer.complete([]);
            }
          }
        },
        onReceivedError: (controller, request, error) {
          _logger.error('WebView load error', tag: 'MirrorFetcher', error: error.description);
          // Load error, complete with empty list
          if (!completer.isCompleted) {
            completer.complete([]);
          }
        },
      );

      headlessWebView = webView;
      // Run the headless webview
      await webView.run();
      _logger.debug('Headless webview started', tag: 'MirrorFetcher');

      // Wait for the page to load and links to be extracted
      // Maximum wait time of 15 seconds
      final result = await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          _logger.warning('Mirror fetch timed out after 15 seconds', tag: 'MirrorFetcher');
          return [];
        },
      );

      _logger.debug('Headless webview completed', tag: 'MirrorFetcher', metadata: {'mirrors_found': result.length});
      return result;
    } catch (e, stackTrace) {
      _logger.error('Failed to fetch mirrors', tag: 'MirrorFetcher', error: e, stackTrace: stackTrace);
      return [];
    } finally {
      try {
        await headlessWebView?.dispose();
        _logger.debug('Headless webview disposed', tag: 'MirrorFetcher');
      } catch (disposeError) {
        _logger.warning('Headless webview dispose failed', tag: 'MirrorFetcher', error: disposeError);
      }
    }
  }
}
