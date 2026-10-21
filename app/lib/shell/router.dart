import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screentime/kid_time.dart';
import '../screentime/child_time_screen.dart';
import '../screentime/more_time_screen.dart';
import '../screentime/screen_time_screen.dart';
import '../screentime/time_rules_screen.dart';
import '../access/check_email_screen.dart';
import '../account/account_screen.dart';
import '../account/data_screen.dart';
import '../account/delete_account_screen.dart';
import '../account/enrollment_screen.dart';
import '../account/email_screen.dart';
import '../account/password_screen.dart';
import '../account/sessions_screen.dart';
import '../account/verification_screen.dart';
import '../access/email_sign_in_screen.dart';
import '../access/entry_screen.dart';
import '../access/forgot_password_screen.dart';
import '../family/accept_invitation_screen.dart';
import '../family/adults_screen.dart';
import '../family/child_screen.dart';
import '../family/children_screen.dart';
import '../family/delete_family_screen.dart';
import '../family/family_home_screen.dart';
import '../family/invitations_screen.dart';
import '../family/new_child_screen.dart';
import '../family/reconsent_screen.dart';
import '../kid/kid_exit_screen.dart';
import '../kid/kid_home_screen.dart';
import '../kid/pack_player_screen.dart';
import '../kid/player_screen.dart';
import '../kid/profile_picker_screen.dart';
import '../kid_mode/devices_screen.dart';
import '../kid_mode/hand_over_screen.dart';
import '../kid_mode/kid_mode_screen.dart';
import '../kid_mode/link_code_screen.dart';
import '../kid_mode/pin_gate_screen.dart';
import '../kid_mode/redeem_screen.dart';
import '../kid_mode/set_pin_screen.dart';
import '../access/link_account_screen.dart';
import '../access/provider_signup_screen.dart';
import '../access/reset_password_screen.dart';
import '../access/signup_screen.dart';
import '../access/verify_email_screen.dart';
import '../auth/api_client.dart';
import '../catalog/catalog_children_screen.dart';
import '../catalog/child_catalog_screen.dart';
import '../catalog/family_video_screen.dart';
import '../catalog/pack_screen.dart';
import '../catalog/report_screen.dart';
import '../curation/family_catalog.dart' show FamilyPack, FamilyVideo;
import '../curation/admin_pack_screen.dart';
import '../curation/admin_packs_screen.dart';
import '../curation/admin_screen.dart';
import '../curation/appoint_screen.dart' show AppointScreen;
import '../curation/compose_pack_screen.dart';
import '../curation/pack.dart';
import '../curation/pack_draft.dart';
import '../curation/pack_decision_screens.dart';
import '../curation/pack_review_screen.dart';
import '../curation/packs_screen.dart';
import '../curation/held_video_screen.dart';
import '../curation/held_videos_screen.dart';
import '../curation/member_screen.dart' show MemberScreen;
import '../curation/team_screen.dart';
import '../curation/team_words.dart' show TeamNotice;
import '../curation/new_suggestion_screen.dart';
import '../curation/approve_screen.dart';
import '../curation/curation.dart' show Video;
import '../curation/queue_screen.dart';
import '../curation/refuse_screen.dart';
import '../curation/review_screen.dart';
import '../curation/role_gate.dart';
import '../curation/suggestions_screen.dart';
import '../auth/provider_sign_in.dart';
import '../design/band_transition.dart';
import '../family/family.dart';
import '../family/family_model.dart';
import '../legal/terms_update_screen.dart';
import '../parental/app_mode.dart';
import '../staff/account_search_screen.dart';
import '../staff/account_sheet_screen.dart';
import '../staff/accounts.dart' show AccountSheet;
import '../staff/audit_screen.dart';
import '../staff/staff_gate.dart';
import 'routes.dart';
import 'services.dart';

/// The UI's access control. It only routes: the server enforces
/// every boundary on its own.
GoRouter buildRouter(AppServices services, {String? initialLocation}) {
  final status = services.client.status;
  final family = services.familyModel;
  final mode = services.appMode;
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: Listenable.merge([
      status,
      services.pending,
      family,
      mode,
    ]),
    redirect: (context, state) {
      // The QR's link first becomes its route; the gate below then
      // decides on it like on any path.
      if (Routes.fromDeepLink(state.uri) case final to?) return to;
      final path = state.matchedLocation;
      // The mode decides before the session does.
      if (_modeRedirect(mode.mode, path) case final to?) return to;
      if (path == Routes.profilePicker && services.profilePick == null) {
        return Routes.kidExit; // the picker opens only behind the PIN
      }
      if (path == Routes.redeem && !services.child.canLink) {
        return Routes.entry; // Android and iOS only
      }
      final pending = services.pending.value;
      if (path == Routes.providerSignup && pending is! SignupRequired) {
        return Routes.entry;
      }
      if (path == Routes.linkAccount && pending is! LinkRequired) {
        return Routes.entry;
      }
      return switch (status.value) {
        AuthStatus.unknown => null,
        AuthStatus.signedOut when path == Routes.acceptInvitation => _hold(
          services,
          state.uri.queryParameters['token'],
        ),
        AuthStatus.signedOut when Routes.signedInOnly(path) => Routes.entry,
        // A suspended account keeps to its own routes. Only in the guardian's mode: the child's
        // modes keep their own gates.
        AuthStatus.signedIn when family.suspended && mode.mode is Guardian =>
          _suspendedRedirect(family.state, path),
        // Then the account waits on the current terms, except for its data
        // and its erasure; the terms screen itself offers signing out.
        // Suspension comes first: its own routes already hold those.
        AuthStatus.signedIn
            when !family.termsAccepted && mode.mode is Guardian =>
          _termsRedirect(family.state, path),
        AuthStatus.signedIn when path == Routes.terms => Routes.home,
        AuthStatus.signedIn when Routes.signedOutOnly.contains(path) =>
          switch (services.heldInvitation) {
            final token? => Routes.invitation(token),
            null => Routes.home,
          },
        AuthStatus.signedIn
            when Routes.isFamilyScreen(path) || Routes.isKidModeScreen(path) =>
          _familyRedirect(family.state, path),
        AuthStatus.signedIn
            when Routes.isCuratorScreen(path) ||
                Routes.isAdminScreen(path) ||
                Routes.isModerationScreen(path) =>
          roleRedirect(family.roles, path),
        // The second factor is for platform role holders (MFA screens,
        // Routes); roles not read yet decide nothing.
        AuthStatus.signedIn
            when Routes.isMfaScreen(path) && (family.roles?.isEmpty ?? false) =>
          Routes.account,
        _ => null,
      };
    },
    routes: [
      GoRoute(
        path: Routes.home,
        // Arriving from an unlock, the child's screen closes back onto the
        // band; any other arrival is the ordinary page.
        pageBuilder: (_, state) => BandArrivalPage(
          key: state.pageKey,
          motion: state.extra == BandMotion.shrink ? BandMotion.shrink : null,
          child: const FamilyHomeScreen(),
        ),
      ),
      GoRoute(path: Routes.adults, builder: (_, _) => const AdultsScreen()),
      GoRoute(
        path: Routes.invitations,
        builder: (_, _) => const InvitationsScreen(),
      ),
      GoRoute(
        path: Routes.children,
        builder: (_, state) => ChildrenScreen(notice: state.extra as String?),
        routes: [
          GoRoute(path: 'nova', builder: (_, _) => const NewChildScreen()),
          GoRoute(
            path: ':id',
            builder: (_, state) => ChildScreen(id: state.pathParameters['id']!),
            routes: [
              GoRoute(
                path: 'autorizar',
                builder: (_, state) => ReconsentScreen(
                  id: state.pathParameters['id']!,
                  then: Routes.reconsentReturn(
                    state.uri.queryParameters['depois'],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: Routes.screenTime,
        builder: (_, state) => ScreenTimeScreen(notice: state.extra as String?),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, state) =>
                ChildTimeScreen(id: state.pathParameters['id']!),
            routes: [
              GoRoute(
                path: 'mais',
                builder: (_, state) =>
                    MoreTimeScreen(id: state.pathParameters['id']!),
              ),
              GoRoute(
                path: 'limite',
                builder: (_, state) =>
                    TimeRulesScreen(id: state.pathParameters['id']!),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: Routes.familyVideos,
        builder: (_, state) => CatalogChildrenScreen(notice: _notice(state)),
        routes: [
          GoRoute(
            path: ':crianca',
            builder: (_, state) => ChildCatalogScreen(
              id: state.pathParameters['crianca']!,
              notice: _notice(state),
            ),
            routes: [
              // Before `:video`, which would take "pacotinho" for an id.
              GoRoute(
                path: 'pacotinho/:pacotinho',
                builder: (_, state) => PackScreen(
                  minorId: state.pathParameters['crianca']!,
                  packId: state.pathParameters['pacotinho']!,
                  pack: switch (state.extra) {
                    final FamilyPack p => p,
                    _ => null,
                  },
                ),
              ),
              GoRoute(
                path: ':video',
                builder: (_, state) => FamilyVideoScreen(
                  minorId: state.pathParameters['crianca']!,
                  videoId: state.pathParameters['video']!,
                  video: _familyVideo(state),
                ),
                routes: [
                  GoRoute(
                    path: 'denunciar',
                    builder: (_, state) => ReportScreen(
                      minorId: state.pathParameters['crianca']!,
                      videoId: state.pathParameters['video']!,
                      video: _familyVideo(state),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: Routes.deleteFamily,
        builder: (_, _) => const DeleteFamilyScreen(),
      ),
      GoRoute(
        path: Routes.kidMode,
        builder: (_, state) => KidModeScreen(saved: state.extra as PinSaved?),
        routes: [
          GoRoute(path: 'pin', builder: (_, _) => const SetPinScreen()),
          GoRoute(path: 'entregar', builder: (_, _) => const HandOverScreen()),
          GoRoute(path: 'vincular', builder: (_, _) => const LinkCodeScreen()),
          GoRoute(path: 'aparelhos', builder: (_, _) => const DevicesScreen()),
        ],
      ),
      GoRoute(
        path: Routes.account,
        builder: (_, _) => const AccountScreen(),
        routes: [
          GoRoute(path: 'email', builder: (_, _) => const EmailScreen()),
          GoRoute(path: 'senha', builder: (_, _) => const PasswordScreen()),
          GoRoute(path: 'aparelhos', builder: (_, _) => const SessionsScreen()),
          GoRoute(path: 'dados', builder: (_, _) => const DataScreen()),
          GoRoute(
            path: 'verificacao',
            // Recovery codes on screen ask before any way off.
            onExit: (_, _) => services.unkeptCodes?.call() ?? true,
            builder: (_, state) => VerificationScreen(notice: _notice(state)),
            routes: [
              GoRoute(
                path: 'ativar',
                onExit: (_, _) => services.unkeptCodes?.call() ?? true,
                // `depois` returns to the staff screen that asked,
                // only ever an admin or moderation one.
                builder: (_, state) => EnrollmentScreen(
                  then: Routes.staffReturn(state.uri.queryParameters['depois']),
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'excluir',
            builder: (_, _) => const DeleteAccountScreen(),
          ),
        ],
      ),
      // The curation areas; each lands its own
      // screen and sub-routes.
      GoRoute(
        path: Routes.suggestions,
        builder: (_, _) => const SuggestionsScreen(),
        routes: [
          GoRoute(path: 'nova', builder: (_, _) => const NewSuggestionScreen()),
        ],
      ),
      GoRoute(
        path: Routes.curation,
        // Beneath a decision the extra is the video it names, not a notice.
        builder: (_, state) => QueueScreen(
          notice: switch (state.extra) {
            final String notice => notice,
            _ => null,
          },
        ),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, state) =>
                ReviewScreen(id: state.pathParameters['id']!),
            routes: [
              GoRoute(
                path: 'aprovar',
                builder: (_, state) => ApproveScreen(
                  id: state.pathParameters['id']!,
                  video: state.extra as Video?,
                ),
              ),
              GoRoute(
                path: 'recusar',
                builder: (_, state) => RefuseScreen(
                  id: state.pathParameters['id']!,
                  video: state.extra as Video?,
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: Routes.packs,
        builder: (_, state) => PacksScreen(notice: _notice(state)),
        routes: [
          GoRoute(
            path: 'novo',
            builder: (_, _) => const ComposePackScreen(),
            routes: [
              GoRoute(
                path: 'videos',
                builder: (_, state) => PackPickerScreen(
                  back: Routes.newPack,
                  draft: _draft(state),
                ),
              ),
            ],
          ),
          GoRoute(
            path: ':id',
            builder: (_, state) =>
                PackReviewScreen(id: state.pathParameters['id']!),
            routes: [
              GoRoute(
                path: 'videos/:video',
                builder: (_, state) => PackVideoScreen(
                  packId: state.pathParameters['id']!,
                  videoId: state.pathParameters['video']!,
                ),
              ),
              GoRoute(
                path: 'mudar',
                builder: (_, state) =>
                    ComposePackScreen(id: state.pathParameters['id']!),
                routes: [
                  GoRoute(
                    path: 'videos',
                    builder: (_, state) => PackPickerScreen(
                      back: Routes.recompose(state.pathParameters['id']!),
                      draft: _draft(state),
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: 'aprovar',
                builder: (_, state) => ApprovePackScreen(
                  id: state.pathParameters['id']!,
                  pack: _pack(state),
                ),
              ),
              GoRoute(
                path: 'recusar',
                builder: (_, state) => RefusePackScreen(
                  id: state.pathParameters['id']!,
                  pack: _pack(state),
                ),
              ),
            ],
          ),
        ],
      ),
      // The admin and moderation screens, each behind the second factor's
      // gate; the curators' never are.
      GoRoute(
        path: Routes.admin,
        builder: (_, _) =>
            const StaffGate(title: 'Administração', child: AdminScreen()),
        routes: [
          GoRoute(
            path: 'equipe',
            builder: (_, state) => StaffGate(
              title: 'Equipe',
              child: TeamScreen(notice: state.extra as TeamNotice?),
            ),
            routes: [
              GoRoute(
                path: 'nova',
                builder: (_, state) => StaffGate(
                  title: 'Nomear alguém',
                  child: AppointScreen(
                    email: state.uri.queryParameters['email'],
                    role: AppointScreen.parsePapel(
                      state.uri.queryParameters['papel'],
                    ),
                  ),
                ),
              ),
              GoRoute(
                path: ':id',
                builder: (_, state) => StaffGate(
                  title: 'Equipe',
                  child: MemberScreen(id: state.pathParameters['id']!),
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'contas',
            builder: (_, state) => StaffGate(
              title: 'Buscar uma conta',
              child: AccountSearchScreen(notice: _notice(state)),
            ),
            routes: [
              // The sheet lives only in memory: without the lookup's
              // answer for this id (a reload, a link), back to the search,
              // never a silent lookup.
              GoRoute(
                path: ':id',
                redirect: (_, state) =>
                    _sheet(state)?.accountId == state.pathParameters['id']
                    ? null
                    : Routes.accounts,
                builder: (_, state) => StaffGate(
                  title: 'Conta',
                  child: AccountSheetScreen(sheet: _sheet(state)!),
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'auditoria',
            builder: (_, _) =>
                const StaffGate(title: 'Auditoria', child: AuditScreen()),
          ),
          GoRoute(
            path: 'pacotinhos',
            builder: (_, state) => StaffGate(
              title: 'Pacotinhos',
              child: AdminPacksScreen(notice: _notice(state)),
            ),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) => StaffGate(
                  title: 'Pacotinho',
                  child: AdminPackScreen(id: state.pathParameters['id']!),
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: Routes.heldVideos,
        builder: (_, state) => StaffGate(
          title: 'Vídeos retidos',
          child: HeldVideosScreen(notice: state.extra as String?),
        ),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, state) => StaffGate(
              title: 'Vídeo retido',
              child: HeldVideoScreen(id: state.pathParameters['id']!),
            ),
          ),
        ],
      ),
      GoRoute(path: Routes.pinGate, builder: (_, _) => const PinGateScreen()),
      GoRoute(
        path: Routes.kidHome,
        // The guardian's band grows into the child's screen.
        pageBuilder: (_, state) =>
            bandGrowPage(key: state.pageKey, child: const KidHomeScreen()),
        routes: [
          GoRoute(path: 'sair', builder: (_, _) => const KidExitScreen()),
          GoRoute(path: 'quem', builder: (_, _) => const ProfilePickerScreen()),
          GoRoute(
            path: 'pacotinho/:id',
            builder: (_, state) => PackPlayerScreen(
              start: switch (state.extra) {
                final PackStart s
                    when s.pack.id == state.pathParameters['id'] =>
                  s,
                _ => null,
              },
            ),
          ),
          GoRoute(
            path: 'assistir/:id',
            builder: (_, state) => PlayerScreen(
              videoId: state.pathParameters['id']!,
              play: switch (state.extra) {
                final KidPlay p => p,
                _ => null,
              },
            ),
          ),
        ],
      ),
      GoRoute(
        path: Routes.redeem,
        builder: (_, state) =>
            RedeemScreen(code: state.uri.queryParameters['codigo']),
      ),
      GoRoute(
        path: Routes.acceptInvitation,
        builder: (_, state) =>
            AcceptInvitationScreen(token: state.uri.queryParameters['token']),
      ),
      GoRoute(
        path: Routes.entry,
        builder: (_, _) => const EntryScreen(),
        routes: [
          GoRoute(path: 'email', builder: (_, _) => const EmailSignInScreen()),
        ],
      ),
      GoRoute(path: Routes.signup, builder: (_, _) => const SignupScreen()),
      GoRoute(
        path: Routes.checkEmail,
        builder: (_, state) => CheckEmailScreen(email: state.extra as String?),
      ),
      GoRoute(
        path: Routes.verifyEmail,
        builder: (_, state) =>
            VerifyEmailScreen(token: state.uri.queryParameters['token']),
      ),
      GoRoute(
        path: Routes.forgotPassword,
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: Routes.resetPassword,
        builder: (_, state) =>
            ResetPasswordScreen(token: state.uri.queryParameters['token']),
      ),
      GoRoute(
        path: Routes.providerSignup,
        builder: (_, _) => ProviderSignupScreen(
          step: services.pending.value as SignupRequired,
        ),
      ),
      GoRoute(path: Routes.terms, builder: (_, _) => const TermsUpdateScreen()),
      GoRoute(
        path: Routes.linkAccount,
        builder: (_, _) =>
            LinkAccountScreen(step: services.pending.value as LinkRequired),
      ),
    ],
  );
}

/// The mode gate. A null mode routes nothing: the
/// splash covers every route until it settles. A child's mode keeps to the
/// child side, so a deep link's code is dropped there; a sign-in
/// that owes the PIN reaches nothing else; a guardian never sees either.
String? _modeRedirect(AppMode? mode, String path) => switch (mode) {
  null => null,
  SharedKid() when !Routes.sharedKidMay(path) => Routes.kidHome,
  LinkedDevice() when !Routes.linkedDeviceMay(path) => Routes.kidHome,
  PinRequired() when path != Routes.pinGate => Routes.pinGate,
  Guardian() when Routes.isKidSide(path) => Routes.home,
  _ => null,
};

/// A signed-out visitor's invitation link waits through sign-in in
/// memory, never in storage.
String _hold(AppServices services, String? token) {
  services.heldInvitation = token;
  return Routes.entry;
}

/// Without a family (or a confirmed email) the family screens send home,
/// where the first use or the verify prompt waits. A
/// guardian never sees the owner's screens.
/// While suspended: home, the data and the erasure for anyone; the
/// adults and the family's deletion for its owner, or while the family is
/// still being read (the screen waits, as for any family screen).
String? _suspendedRedirect(FamilyState state, String path) {
  if (Routes.suspendedMay.contains(path)) return null;
  if (!Routes.suspendedOwnerMay.contains(path)) return Routes.home;
  return _ownerStep(state) ? null : Routes.home;
}

/// Before the current terms are accepted: the terms screen, the data and
/// the erasure for anyone; the erasure's owner steps as while suspended.
String? _termsRedirect(FamilyState state, String path) {
  if (Routes.termsMay.contains(path)) return null;
  if (Routes.termsOwnerMay.contains(path) && _ownerStep(state)) return null;
  return Routes.terms;
}

/// Whether an owner's step may show: for the family's owner, or while the
/// family is still being read (the screen waits, as for any family screen).
bool _ownerStep(FamilyState state) => switch (state) {
  FamilyReady(:final family) when family.role == FamilyRole.owner => true,
  FamilyLoading() || FamilyFailed() => true,
  _ => false,
};

String? _familyRedirect(FamilyState state, String path) => switch (state) {
  NoFamily() || EmailUnverified() => Routes.home,
  FamilyReady(:final family)
      when family.role != FamilyRole.owner && Routes.ownerOnly.contains(path) =>
    Routes.home,
  _ => null,
};

/// A route's notice, when its `extra` is one: a nested route's builder
/// sees the extra its child was given too.
PackDraft? _draft(GoRouterState state) => switch (state.extra) {
  final PackDraft d => d,
  _ => null,
};

Pack? _pack(GoRouterState state) => switch (state.extra) {
  final Pack p => p,
  _ => null,
};

AccountSheet? _sheet(GoRouterState state) => switch (state.extra) {
  final AccountSheet s => s,
  _ => null,
};

String? _notice(GoRouterState state) => switch (state.extra) {
  final String s => s,
  _ => null,
};

FamilyVideo? _familyVideo(GoRouterState state) => switch (state.extra) {
  final FamilyVideo v => v,
  _ => null,
};
