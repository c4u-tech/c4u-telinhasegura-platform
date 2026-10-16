import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'export_download.dart';
import 'export_share.dart';

/// `telinhasegura-dados-YYYY-MM-DD.json`, for the device's local day.
String exportFileName(DateTime local) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'telinhasegura-dados-${local.year}-${two(local.month)}-'
      '${two(local.day)}.json';
}

/// The export as a file held only in memory: never written to app
/// storage, never logged.
class ExportFile {
  ExportFile({required this.name, required String text})
    : bytes = utf8.encode(text);

  static const mimeType = 'application/json';

  final String name;
  final Uint8List bytes;
}

/// Hands [file] to the browser or the share sheet, opened from [origin]
/// (the action's rect, which an iPad's popover needs). True once handed
/// over, false when the guardian dismissed the sheet.
typedef ExportHandover = Future<bool> Function(ExportFile file, {Rect? origin});

/// Where the export text goes: the seam the screen calls, so the file's
/// name, its content and the web/mobile branch are tested without a
/// plugin.
abstract interface class ExportDelivery {
  /// True once [text] reached the download or the share sheet.
  Future<bool> deliver(String text, {Rect? origin});
}

/// A download on the web, the system share sheet on Android and iOS.
class PlatformExportDelivery implements ExportDelivery {
  PlatformExportDelivery({
    this.web = kIsWeb,
    ExportHandover? download,
    ExportHandover? share,
  }) : _download = download ?? browserDownload,
       _share = share ?? shareSheet;

  final bool web;
  final ExportHandover _download;
  final ExportHandover _share;

  @override
  Future<bool> deliver(String text, {Rect? origin}) {
    final file = ExportFile(name: exportFileName(clock.now()), text: text);
    return web ? _download(file) : _share(file, origin: origin);
  }
}
