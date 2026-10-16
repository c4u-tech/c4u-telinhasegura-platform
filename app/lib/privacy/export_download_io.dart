import 'dart:ui' show Rect;

import 'export_delivery.dart';

/// Off the web the export goes to the share sheet; nothing downloads.
Future<bool> browserDownload(ExportFile file, {Rect? origin}) =>
    throw UnsupportedError('A browser download needs the web.');
