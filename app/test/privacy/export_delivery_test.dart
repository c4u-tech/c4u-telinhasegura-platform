import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:telinha_segura/privacy/export_delivery.dart';
import 'package:telinha_segura/privacy/export_share.dart';

/// Records each handover and answers [answer].
class FakeHandover {
  FakeHandover({this.answer = true});

  final bool answer;
  final files = <ExportFile>[];
  final origins = <Rect?>[];

  Future<bool> call(ExportFile file, {Rect? origin}) async {
    files.add(file);
    origins.add(origin);
    return answer;
  }
}

const text =
    '{\n  "format": "telinhasegura.export/1",\n  "nome": "Conceição"\n}';

void main() {
  group('the file', () {
    test('is named for the local date, zero-padded', () {
      expect(
        exportFileName(DateTime(2026, 3, 7, 23, 59)),
        'telinhasegura-dados-2026-03-07.json',
      );
      expect(
        exportFileName(DateTime(2026, 10, 4)),
        'telinhasegura-dados-2026-10-04.json',
      );
    });

    test('holds the text as UTF-8 JSON', () {
      final file = ExportFile(name: 'f.json', text: text);

      expect(utf8.decode(file.bytes), text);
      expect(ExportFile.mimeType, 'application/json');
    });
  });

  group('the branch', () {
    test('the web downloads the file named for the device\'s day', () async {
      final download = FakeHandover();
      final share = FakeHandover();
      final delivery = PlatformExportDelivery(
        web: true,
        download: download.call,
        share: share.call,
      );

      // 23:30 local: the device's day, whatever the UTC date is.
      final handed = await withClock(
        Clock.fixed(DateTime(2026, 10, 4, 23, 30)),
        () => delivery.deliver(text),
      );

      expect(handed, isTrue);
      expect(share.files, isEmpty);
      expect(download.files.single.name, 'telinhasegura-dados-2026-10-04.json');
      expect(utf8.decode(download.files.single.bytes), text);
    });

    test('Android and iOS open the share sheet from the action', () async {
      final download = FakeHandover();
      final share = FakeHandover();
      final delivery = PlatformExportDelivery(
        web: false,
        download: download.call,
        share: share.call,
      );
      const origin = Rect.fromLTWH(16, 500, 358, 56);

      await withClock(
        Clock.fixed(DateTime(2026, 1, 2, 8)),
        () => delivery.deliver(text, origin: origin),
      );

      expect(download.files, isEmpty);
      expect(share.files.single.name, 'telinhasegura-dados-2026-01-02.json');
      expect(utf8.decode(share.files.single.bytes), text);
      expect(share.origins.single, origin);
    });

    test('a dismissed sheet is not a delivery', () async {
      final delivery = PlatformExportDelivery(
        web: false,
        download: FakeHandover().call,
        share: FakeHandover(answer: false).call,
      );

      expect(await delivery.deliver(text), isFalse);
    });
  });

  group('the share sheet', () {
    test('gets the bytes in memory, named and typed, from the action', () {
      final file = ExportFile(
        name: 'telinhasegura-dados-2026-10-04.json',
        text: text,
      );
      const origin = Rect.fromLTWH(16, 500, 358, 56);

      final params = shareParams(file, origin: origin);

      final shared = params.files!.single;
      // No path: the app writes nothing to its storage itself.
      expect(shared.path, isEmpty);
      expect(shared.mimeType, 'application/json');
      expect(params.fileNameOverrides, [file.name]);
      expect(params.sharePositionOrigin, origin);
      expect(params.text, isNull);
    });

    test('only a dismissal is not a delivery', () {
      expect(handedOver(ShareResultStatus.success), isTrue);
      // Android cannot always tell; the sheet did open.
      expect(handedOver(ShareResultStatus.unavailable), isTrue);
      expect(handedOver(ShareResultStatus.dismissed), isFalse);
    });

    test('share_plus stays in the export delivery, out of kid mode', () {
      final importers = [
        for (final file in Directory('lib').listSync(recursive: true))
          if (file is File &&
              file.path.endsWith('.dart') &&
              file.readAsStringSync().contains('package:share_plus'))
            file.path,
      ];

      expect(importers, ['lib/privacy/export_share.dart']);
    });
  });
}
