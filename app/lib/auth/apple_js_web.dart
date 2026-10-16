import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

const _appleJs =
    'https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/pt_BR/appleid.auth.js';

/// Injects Apple JS into the page and completes once it has loaded. No
/// page carries it until the first Apple sign-in;
/// callers share one load through `Once`.
Future<void> loadAppleJs() {
  final done = Completer<void>();
  final script = web.HTMLScriptElement()
    ..src = _appleJs
    ..async = true;
  script.onload = ((web.Event _) => done.complete()).toJS;
  script.onerror = ((web.Event _) {
    script.remove();
    done.completeError(StateError('Apple JS could not be loaded'));
  }).toJS;
  web.document.head!.append(script);
  return done.future;
}
