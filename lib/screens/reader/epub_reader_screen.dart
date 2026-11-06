import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';

import '../../l10n/app_localizations.dart';
import '../../routes/app_routes.dart';
import '../../services/hive_service.dart';
import '../../services/media_store.dart';
import '../../widgets/empty_state.dart';

/// Arguments for EpubReaderScreen
class EpubReaderArgs {
  /// Real filesystem path to the EPUB file (already resolved from a
  /// content:// URI when needed — see [EpubReaderScreen.openIfEpub]).
  final String filePath;
  final String title;

  /// Hive key for the saved reading position (`book_<id>` or the path).
  final String positionKey;

  const EpubReaderArgs({
    required this.filePath,
    required this.title,
    required this.positionKey,
  });
}

/// Built-in EPUB reader: open a downloaded EPUB, turn pages, remember
/// where you stopped. Nothing else — no search, highlights, TOC or
/// settings. Deliberately slim: the package can do all of those, but
/// this screen wires only open / paginate / resume.
class EpubReaderScreen extends StatefulWidget {
  const EpubReaderScreen({super.key});

  /// Open [path] in the built-in reader when it is an EPUB file.
  /// Returns true when the reader was opened. [extension] is the book's
  /// known extension and is only needed for content:// URIs, whose path
  /// carries no file name. A false return means the caller should fall
  /// through to the external opener.
  static Future<bool> openIfEpub(
    BuildContext context, {
    required String path,
    required String? extension,
    required String title,
    required int bookId,
  }) async {
    final lowerPath = path.toLowerCase();
    final isEpub = lowerPath.endsWith('.epub') ||
        (MediaStoreFiles.isContentUri(path) &&
            extension?.toLowerCase() == 'epub');
    if (!isEpub) return false;
    // Content URIs go through the cache copy (same helper the share
    // flow uses); plain paths come back unchanged.
    final filePath = await MediaStoreFiles.shareablePath(path);
    if (filePath == null || filePath.isEmpty) return false;
    if (!context.mounted) return true;
    Navigator.of(context).pushNamed(
      AppRoutes.epubReader,
      arguments: EpubReaderArgs(
        filePath: filePath,
        title: title,
        positionKey: bookId > 0 ? 'book_$bookId' : path,
      ),
    );
    return true;
  }

  @override
  State<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends State<EpubReaderScreen> {
  final _controller = EpubController();
  double _progress = 0;
  bool _loadFailed = false;
  bool _didInit = false;

  String? _currentCfi;
  String? _savedCfi;
  List<String>? _savedLocations;
  late EpubReaderArgs _args;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInit) return;
    _didInit = true;
    _args = ModalRoute.of(context)!.settings.arguments as EpubReaderArgs;
    final saved = HiveService.epubPositionsBox.get(_args.positionKey);
    if (saved is Map) {
      final cfi = saved['cfi'];
      if (cfi is String && cfi.isNotEmpty) _savedCfi = cfi;
      final locations = saved['locations'];
      if (locations is List) {
        _savedLocations = locations.map((e) => e.toString()).toList();
      }
    }
  }

  void _savePosition() {
    final cfi = _currentCfi;
    if (cfi == null || cfi.isEmpty) return;
    HiveService.epubPositionsBox.put(_args.positionKey, {
      'cfi': cfi,
      'locations': _savedLocations ?? <String>[],
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _args.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_progress > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text('${(_progress * 100).round()}%'),
              ),
            ),
        ],
      ),
      body: _loadFailed
          ? EmptyState(
              icon: Icons.book_outlined,
              title: l10n.get('epub_open_failed'),
            )
          : EpubViewer(
              epubController: _controller,
              epubSource: EpubSource.fromFile(File(_args.filePath)),
              initialCfi: _savedCfi,
              initialLocations: _savedLocations,
              displaySettings: EpubDisplaySettings(
                flow: EpubFlow.paginated,
                snap: true,
                fontSize: 18,
                theme: isDark ? EpubTheme.dark() : EpubTheme.light(),
              ),
              onRelocated: (location) {
                _currentCfi = location.startCfi;
                _savePosition();
                if (mounted) {
                  setState(() => _progress = location.progress);
                }
              },
              onLocationsGenerated: (locations) {
                _savedLocations = List<String>.from(locations);
                _savePosition();
              },
              onLoadError: (_) {
                if (mounted) {
                  setState(() => _loadFailed = true);
                }
              },
            ),
    );
  }
}
