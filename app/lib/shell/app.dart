import 'dart:async';

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

class _TelinhaSeguraAppState extends State<TelinhaSeguraApp> {
  late final GoRouter _router = buildRouter(
    widget.services,
    initialLocation: widget.initialLocation,
  );

  /// The mode's start-up read failed: the splash offers a retry.
  final _restoreFailed = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
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
