import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import '../design/theme.dart';
import 'router.dart';
import 'services.dart';
import 'splash.dart';

class TelinhaSeguraApp extends StatefulWidget {
  const TelinhaSeguraApp({
    super.key,
    required this.services,
    this.initialLocation,
  });

  final AppServices services;
  final String? initialLocation;

  @override
  State<TelinhaSeguraApp> createState() => _TelinhaSeguraAppState();
}

class _TelinhaSeguraAppState extends State<TelinhaSeguraApp>
    with WidgetsBindingObserver {
  late final GoRouter _router = buildRouter(
    widget.services,
    initialLocation: widget.initialLocation,
  );

  /// The mode's start-up read failed: the splash offers a retry.
  final _restoreFailed = ValueNotifier(false);

  /// A link the platform pushed while the splash stood in for the router.
  /// iOS delivers the link that launched the app this way, right after the
  /// first frame; nothing would take it before the mode is known.
  RouteInformation? _heldLink;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.services.appMode.addListener(_releaseHeldLink);
    unawaited(_restore());
  }

  @override
  Future<bool> didPushRouteInformation(RouteInformation info) {
    if (widget.services.appMode.mode != null) {
      return SynchronousFuture(false); // the router takes it
    }
    _heldLink = info;
    return SynchronousFuture(true);
  }

  /// Hands the held link to the router once it is mounted, the frame after
  /// the mode settles, as if the platform pushed it then.
  void _releaseHeldLink() {
    if (_heldLink == null || widget.services.appMode.mode == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final link = _heldLink;
      _heldLink = null;
      if (link != null && mounted) {
        _router.routeInformationProvider.didPushRouteInformation(link);
      }
    });
  }

  /// The session first, then the mode it decides.
  Future<void> _restore() async {
    await widget.services.client.restoreStatus();
    await _restoreMode();
  }

  Future<void> _restoreMode() async {
    _restoreFailed.value = false;
    try {
      await widget.services.appMode.restore();
    } on Object {
      if (mounted) _restoreFailed.value = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.services.appMode.removeListener(_releaseHeldLink);
    _router.dispose();
    _restoreFailed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppScope(
    services: widget.services,
    child: MaterialApp.router(
      title: 'Telinha Segura',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: _router,
      // Until the mode is known no route renders, guardian or child;
      // the session restore comes first, so this also
      // covers an unknown status.
      //
      // Status bar icons contrast with the guardian ground of the active
      // theme; kid screens set their own (KidLayout), and leaving them
      // must not keep it.
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: Theme.of(context).brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: ListenableBuilder(
          listenable: Listenable.merge([
            widget.services.appMode,
            _restoreFailed,
          ]),
          builder: (context, _) => widget.services.appMode.mode == null
              ? Splash(onRetry: _restoreFailed.value ? _restoreMode : null)
              : child!,
        ),
      ),
    ),
  );
}
