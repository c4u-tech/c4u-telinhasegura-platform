import 'dart:ui' show Rect;

import 'package:share_plus/share_plus.dart';

import 'export_delivery.dart';

// The only file that imports share_plus: guardian area, never kid mode,
// which allows no third-party SDK, so a child's screen never loads one.

/// The share sheet's request: the bytes as an in-memory file, named and
/// typed, opened from [origin].
///
/// share_plus writes in-memory files to the app's temporary directory
/// to hand them to the sheet (Android also copies them into
/// `cache/share_plus`, cleared on the next share); the OS reclaims both.
ShareParams shareParams(ExportFile file, {Rect? origin}) => ShareParams(
  files: [
    XFile.fromData(file.bytes, mimeType: ExportFile.mimeType, name: file.name),
  ],
  fileNameOverrides: [file.name],
  sharePositionOrigin: origin,
);

/// Whether the sheet took the file: only a dismissal says no. Android
/// cannot always tell, and answers unavailable once the sheet opened.
bool handedOver(ShareResultStatus status) =>
    status != ShareResultStatus.dismissed;

/// Opens the system share sheet with [file].
Future<bool> shareSheet(ExportFile file, {Rect? origin}) async => handedOver(
  (await SharePlus.instance.share(shareParams(file, origin: origin))).status,
);
