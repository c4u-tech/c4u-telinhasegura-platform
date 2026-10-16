import 'dart:async';
import 'dart:js_interop';
import 'dart:ui' show Rect;

import 'package:web/web.dart' as web;

import 'export_delivery.dart';

/// Downloads [file] from an object URL over its in-memory bytes, through
/// a hidden anchor, and revokes the URL once the click is handled.
Future<bool> browserDownload(ExportFile file, {Rect? origin}) async {
  final blob = web.Blob(
    [file.bytes.toJS].toJS,
    web.BlobPropertyBag(type: ExportFile.mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = file.name
    ..style.display = 'none';
  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  // Some browsers read the URL after the click returns.
  Timer(const Duration(seconds: 1), () => web.URL.revokeObjectURL(url));
  return true;
}
