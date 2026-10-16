import 'dart:async';

import 'package:flutter/widgets.dart';

import '../auth/api_client.dart';
import '../auth/auth_api.dart';
import '../auth/device_label.dart';
import '../auth/google_web_sign_in.dart';
import '../auth/provider_authenticator.dart';
import '../auth/provider_sign_in.dart';
import '../curation/curation_api.dart';
import '../curation/family_catalog_api.dart';
import '../family/family_api.dart';
import '../family/family_model.dart';
import '../kid/kid_player.dart';
import '../kid/link_opener.dart';
import '../kid/youtube_kid_player.dart';
import '../parental/app_mode.dart';
import '../parental/child_api.dart';
import '../parental/device_credential_store.dart';
import '../parental/kid_mode_mark.dart';
import '../parental/parental.dart' show Profile;
import '../parental/parental_api.dart';
import '../privacy/export_delivery.dart';
import '../privacy/privacy_api.dart';
import '../screentime/screentime_api.dart';
import '../screentime/time_zone_source.dart';
import '../staff/accounts_api.dart';
import '../staff/elevation_note.dart';
import '../staff/mfa_api.dart';
import '../staff/staff_api.dart';

/// Everything the screens depend on, built once in `main` and handed
/// down by [AppScope] (no state-management package).
class AppServices {
  AppServices({
    required this.client,
    required this.providers,
    required this.settings,
    this.googleWeb,
    DeviceCredentialStore? devices,
    KidModeMark? kidModeMark,
    ExportDelivery? exports,
    DeviceLabelSource? deviceLabel,
    KidPlayer? player,
    KidPlayer? adultPlayer,
    LinkOpener? links,
    TimeZoneSource? timeZone,
  }) : auth = AuthApi(client),
       player = player ?? YouTubeKidPlayer(),
       adultPlayer = adultPlayer ?? YouTubeAdultPlayer(),
       links = links ?? ExternalLinkOpener(),
       timeZone = timeZone ?? PlatformTimeZone(),
       deviceLabel = deviceLabel ?? PlatformDeviceLabel(),
       exports = exports ?? PlatformExportDelivery(),
       family = FamilyApi(client),
       parental = ParentalApi(client),
       child = ChildApi(client, devices: devices),
       privacy = PrivacyApi(client),
       curation = CurationApi(client),
       staff = StaffApi(client),
       mfa = MfaApi(client),
       accounts = AccountsApi(client),
       familyCatalog = FamilyCatalogApi(client) {
    familyModel = FamilyModel(auth: auth, api: family, status: client.status);
    // Any call refused for a suspension re-reads the session; the router
    // then takes the person home (suspension screens).
    client.onSuspended = () => unawaited(familyModel.accountSuspended());
    // A new session, or none, was never elevated.
    client.status.addListener(elevation.forget);
    screenTime = ScreenTimeApi(client, this.timeZone);
    appMode = AppModeModel(
      auth: auth,
      parental: parental,
      child: child,
      client: client,
      mark: kidModeMark ?? MemoryKidModeMark(),
    );
  }

  final ApiClient client;
  final AuthApi auth;
  final FamilyApi family;
  final ParentalApi parental;
  final ChildApi child;
  final PrivacyApi privacy;
  final CurationApi curation;

  /// The team and moderation routes, for an admin or a
  /// moderator.
  final StaffApi staff;

  /// The privileged MFA contract.
  final MfaApi mfa;

  /// The account directory, support and metrics contract, for an
  /// admin.
  final AccountsApi accounts;

  /// This session's elevation as last known, for the staff routes' gate.
  final elevation = ElevationNote();
  final FamilyCatalogApi familyCatalog;

  /// The label every sign-in sends so the guardian can tell sessions
  /// apart, read once per run.
  final DeviceLabelSource deviceLabel;

  /// Where `/conta/dados` hands the export: a download on the web, the
  /// share sheet on Android and iOS.
  final ExportDelivery exports;

  /// The embedded YouTube player the child's videos play in.
  final KidPlayer player;

  /// The same embed with adult settings, for the curator's and admin's
  /// screens: YouTube's own controls, no
  /// autoplay. Its events go through `followAdultPlayer`.
  final KidPlayer adultPlayer;

  /// The device's IANA zone, read when a guardian saves screen-time rules.
  final TimeZoneSource timeZone;

  /// The guardian side of a child's screen-time rules and usage.
  late final ScreenTimeApi screenTime;

  /// Opens a player's link outside the app: behind the PIN in kid mode,
  /// at once on the guardian side.
  final LinkOpener links;

  /// The link a player asked to open, held only while the PIN gate is
  /// open for it: never in a route, never stored or
  /// logged. The gate takes it and lets it go.
  Uri? linkErrand;

  /// Set by the sleeping child home as its exit opens the PIN door, which
  /// takes it at once and then offers more time. Nothing else sets it, so neither a link errand nor a typed
  /// route can become an extension.
  bool moreTimeErrand = false;

  /// Who the app is in front of: guardian, shared kid mode or linked device.
  late final AppModeModel appMode;

  /// The caller's family as the family screens show it.
  late final FamilyModel familyModel;
  final ProviderAuthenticator providers;
  final ProviderSettings settings;

  /// Google's rendered button and token stream; null off the web.
  final GoogleWebSignIn? googleWeb;

  /// The provider step waiting for a confirmation: a [SignupRequired] or
  /// a [LinkRequired]. Its ticket lives only here, never in a URL or in
  /// storage (access-screens Security), so a reload drops it.
  final pending = ValueNotifier<ProviderSignInResult?>(null);

  /// The token a signed-out visitor opened `/convite` with, held only
  /// here through sign-in or signup, where the router hands it back to
  /// `/convite`, whose screen lets it go. Never stored or
  /// logged, and a reload drops it: the emailed link still works.
  String? heldInvitation;

  /// The PIN the exit gate checked on a linked device and the family's
  /// children it answered, held only while the profile picker is open,
  /// for its one re-bind: never in a route, never stored
  /// or logged. The picker drops it when it closes, and the router keeps
  /// the picker shut without it.
  ({String pin, List<Profile> profiles})? profilePick;

  /// Asks before leaving recovery codes not yet kept ("Sair sem guardar os códigos?"),
  /// set only while they are on screen:
  /// the `/conta/verificacao` routes' `onExit` calls it, so browser back
  /// and every other way off the route ask first. True to leave. The codes
  /// themselves stay in the screen's state.
  Future<bool> Function()? unkeptCodes;

  /// Set by a successful link and read once by the home screen, which
  /// greets the linked account with "o sol sobe".
  bool justLinked = false;

  /// A calm line for the entry screen, which takes it once: why the app
  /// was signed out, such as an unlock that found the family gone.
  String? entryNotice;

  /// What the player hands back to the child home, which stays beneath
  /// it: a kid error note to show, and whether the shelves must be read
  /// again. The home takes it and clears it.
  final kidReturn = ValueNotifier<KidReturn?>(null);
}

/// A note for the child home, and whether its shelves changed.
typedef KidReturn = ({String? note, bool refetch});

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.services;

  @override
  bool updateShouldNotify(AppScope old) => old.services != services;
}
