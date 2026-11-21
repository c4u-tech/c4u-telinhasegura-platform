import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import '../design/theme.dart';
import '../parental/app_mode.dart';
import 'router.dart';
import 'services.dart';
import 'splash.dart';
import 'start_failed.dart';
import 'system_bars.dart';

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

  /// Whether a child holds the device, as last known: an unknown mode
  /// between two known ones keeps it.
  bool _childHolds = false;

  /// The mode's start-up read: how many tries failed, and whether one
  /// is under way. Once one failed, its screen offers to try again and
  /// stands, busy while a try runs, until the mode is known.
  final _restoring = ValueNotifier((failures: 0, trying: true));

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

  /// The session's status has been read: a retry reads only the mode.
  bool _statusKnown = false;

  /// The session first, then the mode it decides; a retry does the same,
  /// from where the last try failed. Either failing lands on the failed
  /// start, so the opening never waits on a read that will not come.
  Future<void> _restore() async {
    final failures = _restoring.value.failures;
    _restoring.value = (failures: failures, trying: true);
    final appMode = widget.services.appMode;
    try {
      if (!_statusKnown) {
        try {
          await widget.services.client.restoreStatus();
        } on Object {
          await appMode.startFailed();
          rethrow;
        }
        _statusKnown = true;
      }
      await appMode.restore();
      if (mounted) _restoring.value = (failures: 0, trying: false);
    } on Object {
      if (mounted) _restoring.value = (failures: failures + 1, trying: false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.services.appMode.removeListener(_releaseHeldLink);
    _router.dispose();
    _restoring.dispose();
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
      // The system bars are clear and their icons contrast with the
      // guardian ground of the active theme; kid screens set their own
      // (KidLayout), and leaving them must not keep it. While a child
      // holds the device the bars are hidden.
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: barsOver(Theme.of(context).brightness),
        child: ListenableBuilder(
          listenable: Listenable.merge([widget.services.appMode, _restoring]),
          builder: (context, _) {
            final appMode = widget.services.appMode;
            final mode = appMode.mode;
            final restore = _restoring.value;
            final failed = mode == null && restore.failures > 0;
            if (mode != null) {
              _childHolds = mode is SharedKid || mode is LinkedDevice;
            } else if (failed) {
              _childHolds = appMode.childMayHold;
            }
            return ModeBars(
              hidden: _childHolds,
              child: Opening(
                ready: mode != null,
                failure: failed
                    ? StartFailed(
                        onRetry: _restore,
                        busy: restore.trying,
                        child: appMode.childMayHold,
                        attempt: restore.failures,
                      )
                    : null,
                child: child!,
              ),
            );
          },
        ),
      ),
    ),
  );
}
