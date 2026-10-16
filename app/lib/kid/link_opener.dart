import 'package:url_launcher/url_launcher.dart';

/// Opens a link outside the app, in the system browser or the app that
/// owns it: on the child side only ever after the parents' PIN.
/// True once something took it; false, or an
/// error, when nothing could (an `otpauth://` link with no authenticator installed).
// The app's seam over url_launcher, so tests open nothing.
abstract interface class LinkOpener {
  Future<bool> open(Uri url);
}

class ExternalLinkOpener implements LinkOpener {
  @override
  Future<bool> open(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);
}
