import '../auth/auth_api.dart' show PlatformRole;
import '../curation/shared_link.dart';

/// The app's routes.
/// `/verificar-email`, `/esqueci-a-senha`, `/redefinir-senha` and
/// `/convite` are fixed by the backend's mail
/// (backend/internal/identity/service.go, account.go, messages.go; the
/// family invitation mail).
abstract final class Routes {
  static const home = '/';
  static const entry = '/entrar';
  static const emailSignIn = '/entrar/email';
  static const signup = '/criar-conta';
  static const checkEmail = '/verifique-seu-email';
  static const verifyEmail = '/verificar-email';
  static const forgotPassword = '/esqueci-a-senha';
  static const resetPassword = '/redefinir-senha';
  static const providerSignup = '/concluir-cadastro';
  static const linkAccount = '/vincular-conta';

  /// Where a guardian who has not accepted the current terms and privacy
  /// policy waits until they do or sign out.
  static const terms = '/termos';

  /// The family's areas, the Família destination's root.
  static const family = '/familia';

  /// The staff areas a session's platform roles open, the Equipe
  /// destination's root.
  static const staffHome = '/equipe';

  static const children = '/familia/criancas';
  static const newChild = '/familia/criancas/nova';
  static const adults = '/familia/responsaveis';
  static const invitations = '/familia/convites';
  static const deleteFamily = '/familia/excluir';

  /// Under it, a child's screen-time errands; on its own, and with a child
  /// alone, it leads to the children and to the child's page.
  static const screenTime = '/familia/tempo';

  /// Under it, everything one child can watch, one video, its report and
  /// a pacotinho; on its own it leads to the children.
  static const familyVideos = '/familia/videos';
  static const acceptInvitation = '/convite';

  /// A new family's guided first run: registering a child, creating the
  /// PIN, then handing the device over. It belongs to the home, which it
  /// opens from and returns to.
  static const firstRun = '/comecar';

  /// The first run, naming the child it registered, so a screen opened
  /// from its last step comes back to the same child.
  static String firstRunFor({String? child}) => Uri(
    path: firstRun,
    queryParameters: child == null ? null : {'crianca': child},
  ).toString();

  static const kidMode = '/modo-crianca';
  static const setPin = '/modo-crianca/pin';
  static const handOver = '/modo-crianca/entregar';
  static const linkCode = '/modo-crianca/vincular';
  static const devices = '/modo-crianca/aparelhos';
  static const pinGate = '/pin';
  static const kidHome = '/crianca';
  static const kidExit = '/crianca/sair';
  static const profilePicker = '/crianca/quem';

  /// The player for one of our videos: `/crianca/assistir/:id`.
  static const kidWatch = '/crianca/assistir';

  /// A pacotinho's player: `/crianca/pacotinho/:id`.
  static const kidPack = '/crianca/pacotinho';
  static const redeem = '/vincular-aparelho';

  /// The curation screens: suggestions for
  /// every guardian, the queue for curators, administration for admins.
  static const suggestions = '/sugestoes';
  static const newSuggestion = '/sugestoes/nova';
  static const curation = '/curadoria';
  static const admin = '/admin';

  /// The curator terms, which a curator accepts before any review; its
  /// `depois` is the curation screen that asked, kept by
  /// [curatorTermsReturn].
  static const curatorTerms = '/curadoria/termo';

  static String curatorTermsFor({String? then}) => Uri(
    path: curatorTerms,
    queryParameters: then == null ? null : {'depois': then},
  ).toString();

  /// [raw] when it is a curation screen of this app other than the terms,
  /// its query kept; [curation] for anything else, so `depois` never leads
  /// outside the curation (no open redirect).
  static String curatorTermsReturn(String? raw) {
    final uri = raw == null ? null : Uri.tryParse(raw);
    if (uri == null ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.hasFragment ||
        !uri.path.startsWith('/') ||
        uri.pathSegments.any((s) => s.isEmpty || s == '.' || s == '..') ||
        !isCuratorScreen(uri.path) ||
        uri.path == curatorTerms) {
      return curation;
    }
    return uri.toString();
  }

  /// The team: who holds which platform role,
  /// appointing someone, and one member's sheet, for an admin.
  static const team = '/admin/equipe';
  static const appoint = '/admin/equipe/nova';

  /// The account directory: one
  /// account's reasoned search, and the staff audit log, for an admin.
  static const accounts = '/admin/contas';
  static const audit = '/admin/auditoria';

  /// The moderation screens: the held videos,
  /// for a moderator or an admin.
  static const moderation = '/moderacao';
  static const heldVideos = '/moderacao/retidos';

  /// The audit of recent approvals, for a moderator or an admin: the
  /// sample, then one video of it.
  static const auditSample = '/moderacao/auditoria';

  /// The pacotinhos' curation:
  /// composing and reviewing for curators, removal for admins.
  static const packs = '/pacotinhos';
  static const newPack = '/pacotinhos/novo';
  static const newPackVideos = '/pacotinhos/novo/videos';
  static const adminPacks = '/admin/pacotinhos';

  static const account = '/conta';
  static const accountEmail = '/conta/email';
  static const accountPassword = '/conta/senha';
  static const accountSessions = '/conta/aparelhos';
  static const accountData = '/conta/dados';
  static const accountDelete = '/conta/excluir';

  /// The second factor of a platform role holder:
  /// its status and new recovery codes, then its enrollment.
  static const accountMfa = '/conta/verificacao';
  static const accountMfaEnroll = '/conta/verificacao/ativar';

  /// The enrollment, returning on completion to [then], the staff screen
  /// that asked for it. The admin and moderation
  /// routes' gate opens it as `context.go(Routes.mfaEnrollment(then:
  /// path))`; a [then] [staffReturn] refuses is dropped on arrival, and
  /// the enrollment ends on [accountMfa] instead.
  static String mfaEnrollment({String? then}) => Uri(
    path: accountMfaEnroll,
    queryParameters: then == null ? null : {'depois': then},
  ).toString();

  /// [raw] when it is an admin or moderation screen of this app, its query
  /// kept; null for anything else, so the enrollment's `depois` can never
  /// lead outside the app or to another area (no open redirect).
  static String? staffReturn(String? raw) {
    final uri = raw == null ? null : Uri.tryParse(raw);
    if (uri == null ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.hasFragment ||
        !uri.path.startsWith('/') ||
        uri.pathSegments.any((s) => s.isEmpty || s == '.' || s == '..')) {
      return null;
    }
    if (!isAdminScreen(uri.path) && !isModerationScreen(uri.path)) return null;
    return uri.toString();
  }

  /// The two links the app opens from outside, as the route each stands for:
  /// the guardian's QR, `telinhasegura://vincular?codigo=`, and a share from
  /// the YouTube app, `telinhasegura://sugerir?texto=` (the shared text, from
  /// which the video link is taken). The host names the link and the path is
  /// empty, so neither matches a route as it comes. Null for any other
  /// location. The mode gate then decides, as for the path form.
  static String? fromDeepLink(Uri uri) {
    if (uri.scheme != linkScheme) return null;
    if (uri.path.isNotEmpty && uri.path != '/') return null;
    switch (uri.host) {
      case 'vincular':
        final code = uri.queryParameters['codigo'];
        return Uri(
          path: redeem,
          queryParameters: code == null ? null : {'codigo': code},
        ).toString();
      case 'sugerir':
        final link = youtubeLinkIn(uri.queryParameters['texto']);
        return Uri(
          path: newSuggestion,
          queryParameters: link == null ? null : {'link': link},
        ).toString();
    }
    return null;
  }

  /// Registered on Android and iOS only (AndroidManifest.xml, Info.plist).
  static const linkScheme = 'telinhasegura';

  static String invitation(String token) =>
      Uri(path: acceptInvitation, queryParameters: {'token': token}).toString();

  /// A child's page: the day, the videos and the profile.
  static String child(String id) => '$children/${Uri.encodeComponent(id)}';

  /// The form that edits a child's nickname, avatar and age band.
  static String editChild(String id) => '${child(id)}/editar';

  /// A child's new authorization, returning on completion to [then] when
  /// [reconsentReturn] accepts it, and to [children] otherwise.
  static String reconsent(String id, {String? then}) => Uri(
    path: '${child(id)}/autorizar',
    queryParameters: then == null ? null : {'depois': then},
  ).toString();

  /// [raw] when it is a screen a new authorization may return to (the
  /// hand-over that asked for it); null for anything else, so `depois`
  /// never leads elsewhere.
  static String? reconsentReturn(String? raw) =>
      raw == handOver ? handOver : null;

  /// The link code, returning on back to [then] when [linkCodeReturn]
  /// accepts it.
  static String linkCodeFrom(String then) =>
      Uri(path: linkCode, queryParameters: {'depois': then}).toString();

  /// [raw] when it is the first run (its query kept); null for anything
  /// else, so `depois` never leads outside the app or elsewhere in it.
  static String? linkCodeReturn(String? raw) {
    final uri = raw == null ? null : Uri.tryParse(raw);
    if (uri == null ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.hasFragment ||
        uri.path != firstRun) {
      return null;
    }
    return uri.toString();
  }

  static String childTime(String id) =>
      '$screenTime/${Uri.encodeComponent(id)}';

  static String moreTime(String id) => '${childTime(id)}/mais';

  static String timeRules(String id) => '${childTime(id)}/limite';

  static String childVideos(String minorId) =>
      '$familyVideos/${Uri.encodeComponent(minorId)}';

  static String familyVideo(String minorId, String videoId) =>
      '${childVideos(minorId)}/${Uri.encodeComponent(videoId)}';

  static String reportVideo(String minorId, String videoId) =>
      '${familyVideo(minorId, videoId)}/denunciar';

  /// One of the child's pacotinhos today, read by a guardian.
  static String familyPack(String minorId, String packId) =>
      '${childVideos(minorId)}/pacotinho/${Uri.encodeComponent(packId)}';

  /// The review of one queued video, and its two decisions.
  static String review(String videoId) =>
      '$curation/${Uri.encodeComponent(videoId)}';

  static String approve(String videoId) => '${review(videoId)}/aprovar';

  /// The refusal, with the questions an approval marked as appearing
  /// ticked on arrival.
  static String refuse(String videoId, {List<String> items = const []}) => Uri(
    path: '${review(videoId)}/recusar',
    queryParameters: items.isEmpty ? null : {'itens': items.join(',')},
  ).toString();

  /// The refusal's `itens` as question IDs; none for anything empty.
  static List<String> refuseItems(String? raw) => raw == null || raw.isEmpty
      ? const []
      : [
          for (final id in raw.split(','))
            if (id.isNotEmpty) id,
        ];

  /// One member's sheet.
  static String member(String accountId) =>
      '$team/${Uri.encodeComponent(accountId)}';

  /// The appoint form with [email] and [role] filled in: `papel` is
  /// `curadoria` or `moderacao`.
  static String appointFor(String email, PlatformRole role) => Uri(
    path: appoint,
    queryParameters: {
      'email': email,
      'papel': role == PlatformRole.moderator ? 'moderacao' : 'curadoria',
    },
  ).toString();

  /// One account's sheet, opened only by a lookup.
  static String accountSheet(String accountId) =>
      '$accounts/${Uri.encodeComponent(accountId)}';

  static String auditVideo(String videoId) =>
      '$auditSample/${Uri.encodeComponent(videoId)}';

  static String heldVideo(String videoId) =>
      '$heldVideos/${Uri.encodeComponent(videoId)}';

  /// Publishing a video a curator's doubt holds.
  static String publishDoubt(String videoId) =>
      '${heldVideo(videoId)}/publicar';

  /// The review of one pacotinho, and what opens from it.
  static String packReview(String packId) =>
      '$packs/${Uri.encodeComponent(packId)}';

  static String packVideo(String packId, String videoId) =>
      '${packReview(packId)}/videos/${Uri.encodeComponent(videoId)}';

  static String approvePack(String packId) => '${packReview(packId)}/aprovar';

  static String refusePack(String packId) => '${packReview(packId)}/recusar';

  static String recompose(String packId) => '${packReview(packId)}/mudar';

  static String recomposeVideos(String packId) => '${recompose(packId)}/videos';

  static String adminPack(String packId) =>
      '$adminPacks/${Uri.encodeComponent(packId)}';

  static String watch(String videoId) =>
      '$kidWatch/${Uri.encodeComponent(videoId)}';

  /// A player's path: one id segment under [kidWatch].
  static bool isWatch(String path) =>
      path.startsWith('$kidWatch/') &&
      path.length > kidWatch.length + 1 &&
      !path.substring(kidWatch.length + 1).contains('/');

  static String pack(String packId) =>
      '$kidPack/${Uri.encodeComponent(packId)}';

  /// A pacotinho's path: one id segment under [kidPack].
  static bool isPack(String path) =>
      path.startsWith('$kidPack/') &&
      path.length > kidPack.length + 1 &&
      !path.substring(kidPack.length + 1).contains('/');

  static const signedOutOnly = {
    entry,
    emailSignIn,
    signup,
    providerSignup,
    linkAccount,
    redeem,
  };

  /// The home and its first run, the terms screen and everything under `/familia`,
  /// `/modo-crianca`, `/conta`, `/equipe` and the curation and moderation
  /// screens. `/convite` is not here: a
  /// signed-out visitor keeps the token through sign-in.
  static bool signedInOnly(String path) =>
      path == home ||
      path == terms ||
      path == firstRun ||
      isFamilyScreen(path) ||
      isKidModeScreen(path) ||
      isAccountScreen(path) ||
      isSuggestionScreen(path) ||
      isCuratorScreen(path) ||
      isAdminScreen(path) ||
      isModerationScreen(path) ||
      path == staffHome;

  static bool _under(String root, String path) =>
      path == root || path.startsWith('$root/');

  /// A guardian's own suggestions, for every guardian.
  static bool isSuggestionScreen(String path) => _under(suggestions, path);

  /// The queue, the review and the pacotinhos: for a session holding
  /// `curator`.
  static bool isCuratorScreen(String path) =>
      _under(curation, path) || _under(packs, path);

  /// The team, the pacotinhos and the account directory: for a session
  /// holding `admin`.
  static bool isAdminScreen(String path) => _under(admin, path);

  /// The held videos: for a session holding `moderator` or `admin`.
  static bool isModerationScreen(String path) => _under(moderation, path);

  static bool isFamilyScreen(String path) => _under(family, path);

  /// The staff areas: the Equipe root and every curator, admin and
  /// moderation screen.
  static bool isStaffScreen(String path) =>
      path == staffHome ||
      isCuratorScreen(path) ||
      isAdminScreen(path) ||
      isModerationScreen(path);

  /// The guardian's own account, with or without a family or a
  /// confirmed email.
  static bool isAccountScreen(String path) =>
      path == account || path.startsWith('$account/');

  /// The second factor's screens: for a session holding any platform
  /// role.
  static bool isMfaScreen(String path) => _under(accountMfa, path);

  /// The guardian's kid-mode screens, for members only.
  static bool isKidModeScreen(String path) =>
      path == kidMode || path.startsWith('$kidMode/');

  /// Where a child's mode may stay; anything else lands on [kidHome].
  /// Only a linked device picks a profile. Both play a
  /// video and a pacotinho.
  static const sharedKidOnly = {kidHome, kidExit};
  static const linkedDeviceOnly = {kidHome, kidExit, profilePicker};

  static bool sharedKidMay(String path) =>
      sharedKidOnly.contains(path) || isWatch(path) || isPack(path);

  static bool linkedDeviceMay(String path) =>
      linkedDeviceOnly.contains(path) || isWatch(path) || isPack(path);

  /// The child side and the PIN gate, which a guardian never sees.
  static bool isKidSide(String path) =>
      path == pinGate || path == kidHome || path.startsWith('$kidHome/');

  /// Hidden from guardians; the server still answers `not_owner`.
  static const ownerOnly = {invitations, deleteFamily};

  /// Where a suspended account may go (suspension screens): its
  /// home, its data and its erasure, and, for the family's owner, the two
  /// steps the erasure asks of them. Anything else goes home.
  static const suspendedMay = {home, accountData, accountDelete};
  static const suspendedOwnerMay = {adults, deleteFamily};

  /// Where an account that has not accepted the current terms may go
  /// besides the terms screen: its data and its erasure, and, for the
  /// family's owner, the two steps the erasure asks of them. Seeing and
  /// erasing one's own data never waits on an agreement.
  static const termsMay = {terms, accountData, accountDelete};
  static const termsOwnerMay = suspendedOwnerMay;
}
