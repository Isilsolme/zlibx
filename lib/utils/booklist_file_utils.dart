import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/booklist_share_codec.dart';

class BooklistFileUtils {
  /// 把书单写入临时 JSON 并调起系统分享。
  static Future<void> exportAndShare(BooklistShareData data) async {
    final json = BooklistShareCodec.encodeJsonFile(data);
    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/olib_booklist_$ts.json');
    await file.writeAsString(json);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        text: 'zlibx booklist (${data.entries.length} books)',
      ),
    );
  }

  /// 让用户选一个 JSON 文件并解析。
  static Future<BooklistShareData?> pickAndParse() async {
    // file_picker 13.x: pickFiles() returns List<PlatformFile> (empty
    // on cancel); the old FilePickerResult + withData are gone. Read
    // the content via readAsBytes().
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (files.isEmpty) return null;
    final selectedFile = files.first;
    final selectedPath = selectedFile.path;
    if (selectedPath != null) {
      final fileSize = await File(selectedPath).length();
      if (fileSize > BooklistShareCodec.maxFileBytes) return null;
    }

    final bytes = await selectedFile.readAsBytes();
    if (bytes.length > BooklistShareCodec.maxFileBytes) return null;
    final content = utf8.decode(bytes);
    return BooklistShareCodec.tryDecode(content);
  }
}
