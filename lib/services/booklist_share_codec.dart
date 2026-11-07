import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:io' show gzip;

import 'package:olib_api_plugin/olib_api_plugin.dart';

class BooklistShareData {
  final List<BooklistEntry> entries;
  final String? name;
  final DateTime? exportedAt;

  const BooklistShareData({
    required this.entries,
    this.name,
    this.exportedAt,
  });

  bool get hasMetadata => entries.any((e) => e.title != null);
  int get length => entries.length;
}

class BooklistEntry {
  final String id;
  final String? title;
  final String? author;
  final String? hash;

  const BooklistEntry({
    required this.id,
    this.title,
    this.author,
    this.hash,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        if (title != null) 't': title,
        if (author != null) 'a': author,
        if (hash != null) 'h': hash,
      };

  factory BooklistEntry.fromJson(Map<String, dynamic> j) => BooklistEntry(
        id: j['id'].toString(),
        title: j['t'] as String?,
        author: j['a'] as String?,
        hash: j['h'] as String?,
      );

  factory BooklistEntry.fromBook(Book b) => BooklistEntry(
        id: b.id.toString(),
        title: b.title,
        author: b.author,
        hash: b.hash,
      );
}

/// 统一的书单编解码。
///
/// 三种载体：
/// - 紧凑 URI:       olib://booklist?ids=123,456,789  （二维码首选）
/// - 完整 URI:       `olib://booklist?d=<base64url(gzip(json))>`  （口令/带元数据二维码）
/// - JSON 文件 (.json):  {"v":1,"name":...,"exportedAt":...,"books":[...]}
///
/// 兼容旧格式 `olib_share:123,456`。
class BooklistShareCodec {
  static const String scheme = 'olib';
  static const String host = 'booklist';
  static const int formatVersion = 1;

  /// 二维码可承载的近似字符上限（QR v40 + 中等纠错，留余量）
  static const int qrSafeChars = 1800;

  /// 入站分享的安全上限：`d` 参数（base64url）超过它直接拒绝，
  /// gzip 解压产物超过它直接失败，书目条数超过它直接截断，
  /// 分享进来的文件超过它不读。
  /// 不设上限时别的应用能发一个压缩炸弹把本应用撑爆。
  static const int maxDParamChars = 512 * 1024;
  static const int maxGzipOutputBytes = 2 * 1024 * 1024;
  static const int maxBookEntries = 2000;
  static const int maxFileBytes = 2 * 1024 * 1024;

  /// 把书单编成紧凑 URI（仅 ID）
  static String encodeIdsUri(Iterable<String> ids) {
    final cleaned = ids.where((e) => e.trim().isNotEmpty).join(',');
    return '$scheme://$host?ids=$cleaned';
  }

  /// 把书单编成完整 URI（含元数据）
  static String encodeFullUri(BooklistShareData data) {
    final payload = <String, dynamic>{
      'v': formatVersion,
      if (data.name != null) 'n': data.name,
      if (data.exportedAt != null) 'e': data.exportedAt!.toIso8601String(),
      'b': data.entries.map((e) => e.toJson()).toList(),
    };
    final raw = utf8.encode(jsonEncode(payload));
    final compressed = gzip.encode(raw);
    final b64 = base64UrlEncode(compressed);
    return '$scheme://$host?d=$b64';
  }

  /// 为二维码挑选合适的编码：先试完整版，超长则降级到纯 ID。
  static String encodeForQr(BooklistShareData data) {
    final full = encodeFullUri(data);
    if (full.length <= qrSafeChars) return full;
    return encodeIdsUri(data.entries.map((e) => e.id));
  }

  /// 把书单序列化为 JSON 文件内容（导出/备份）
  static String encodeJsonFile(BooklistShareData data) {
    return const JsonEncoder.withIndent('  ').convert({
      'v': formatVersion,
      if (data.name != null) 'name': data.name,
      'exportedAt': (data.exportedAt ?? DateTime.now()).toIso8601String(),
      'books': data.entries
          .map((e) => {
                'id': e.id,
                if (e.title != null) 'title': e.title,
                if (e.author != null) 'author': e.author,
                if (e.hash != null) 'hash': e.hash,
              })
          .toList(),
    });
  }

  /// 万能解析：URI / 旧 olib_share / JSON 文本 都能塞进来
  static BooklistShareData? tryDecode(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty || utf8.encode(trimmed).length > maxFileBytes) {
      return null;
    }

    // 1) JSON 文件
    if (trimmed.startsWith('{')) {
      try {
        final m = jsonDecode(trimmed) as Map<String, dynamic>;
        return _fromJsonMap(m);
      } catch (error) { debugPrint('[booklist_share_codec] ignored ${error.runtimeType}'); }
    }

    // 2) 旧协议 olib_share:id1,id2
    if (trimmed.startsWith('olib_share:')) {
      final body = trimmed.substring('olib_share:'.length);
      final ids = body
          .split(',')
          .map((e) => e.split(':').first.trim())
          .where((e) => e.isNotEmpty)
          .take(maxBookEntries)
          .toList();
      if (ids.isEmpty) return null;
      return BooklistShareData(
        entries: ids.map((id) => BooklistEntry(id: id)).toList(),
      );
    }

    // 3) URI
    Uri? uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (error) {
      debugPrint('[booklist_share_codec] ignored ${error.runtimeType}');
      return null;
    }
    if (uri.scheme != scheme || uri.host != host) return null;

    // 3a) 完整版 d=
    final d = uri.queryParameters['d'];
    if (d != null && d.isNotEmpty) {
      // 拒绝超长参数：base64 解码和 gzip 解压之前先拦住。
      if (d.length > maxDParamChars) return null;
      try {
        final bytes = base64Url.decode(_padBase64(d));
        final json = utf8.decode(_decodeGzipCapped(bytes));
        final m = jsonDecode(json) as Map<String, dynamic>;
        return _fromJsonMap(m, compact: true);
      } catch (error) {
        debugPrint('[booklist_share_codec] ignored ${error.runtimeType}');
        return null;
      }
    }

    // 3b) 紧凑版 ids=
    final idsParam = uri.queryParameters['ids'];
    if (idsParam != null && idsParam.isNotEmpty) {
      final ids = idsParam
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .take(maxBookEntries)
          .toList();
      if (ids.isEmpty) return null;
      return BooklistShareData(
        entries: ids.map((id) => BooklistEntry(id: id)).toList(),
        name: uri.queryParameters['n'],
      );
    }

    return null;
  }

  static BooklistShareData _fromJsonMap(Map<String, dynamic> m,
      {bool compact = false}) {
    final booksKey = compact ? 'b' : 'books';
    final nameKey = compact ? 'n' : 'name';
    final dateKey = compact ? 'e' : 'exportedAt';

    final rawBooks = (m[booksKey] ?? m['books'] ?? m['b']) as List?;
    if (rawBooks == null) {
      return const BooklistShareData(entries: []);
    }
    final entries = rawBooks
        .whereType<Map>()
        .where((e) {
          final id = e['id'];
          return (id is String && id.trim().isNotEmpty) || id is num;
        })
        .map((e) => BooklistEntry.fromJson({
              'id': e['id'],
              't': e['t'] ?? e['title'],
              'a': e['a'] ?? e['author'],
              'h': e['h'] ?? e['hash'],
            }))
        .where((e) => e.id.isNotEmpty && e.id != 'null')
        .take(maxBookEntries)
        .toList();

    DateTime? exportedAt;
    final eRaw = m[dateKey] ?? m['exportedAt'] ?? m['e'];
    if (eRaw is String) {
      exportedAt = DateTime.tryParse(eRaw);
    }

    return BooklistShareData(
      entries: entries,
      name: (m[nameKey] ?? m['name'] ?? m['n']) as String?,
      exportedAt: exportedAt,
    );
  }

  static String _padBase64(String s) {
    final pad = (4 - s.length % 4) % 4;
    return s + '=' * pad;
  }

  /// 解压 gzip，但产物超过 [maxGzipOutputBytes] 时抛异常（而不是
  /// 把几百 MB 的压缩炸弹整个解到内存里）。调用方捕获后返回 null。
  static List<int> _decodeGzipCapped(List<int> bytes) {
    final sink = _CappedBytesSink(maxGzipOutputBytes);
    final conversion = gzip.decoder.startChunkedConversion(sink);
    conversion.add(bytes);
    conversion.close();
    return sink.out.takeBytes();
  }
}

/// 分块收集 gzip 解压产物，超过上限立刻抛异常，中断解压。
class _CappedBytesSink extends ByteConversionSinkBase {
  final BytesBuilder out = BytesBuilder(copy: false);
  final int maxBytes;

  _CappedBytesSink(this.maxBytes);

  @override
  void add(List<int> chunk) {
    out.add(chunk);
    if (out.length > maxBytes) {
      throw FormatException(
        'gzip output exceeds $maxBytes bytes',
      );
    }
  }

  @override
  void close() {}
}
