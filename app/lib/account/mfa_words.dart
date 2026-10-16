import '../auth/api_error.dart';
import '../auth/auth_api.dart' show PlatformRole;
import '../staff/mfa.dart';
import 'sessions_screen.dart' show sessionSince;

/// The second factor's name, as its door and its screen title say it.
const mfaTitle = 'Verificação em duas etapas';

/// The door's line when the status cannot be read.
const mfaUnknown = 'Indisponível no momento';

/// `mfa_unavailable` on the factor's screens: the server has no key.
const mfaUnavailable =
    'A verificação está indisponível no momento. Tente mais tarde.';

/// When the factor was enrolled, as its local day: "Ativada desde 7 de
/// outubro", with the year only when it is not [now]'s.
String mfaEnrolledSince(DateTime enrolledAt, DateTime now) =>
    'Ativada ${sessionSince(enrolledAt, now)}';

/// The "Verificação em duas etapas" door's line: the
/// enrollment's day, or what the factor is for in [roles]; null while
/// [status] is read, and [mfaUnknown] when it could not be ([error]).
String? mfaDoorLine(
  MfaStatus? status,
  Set<PlatformRole> roles,
  DateTime now, {
  Object? error,
}) {
  if (error != null) return mfaUnknown;
  if (status == null) return null;
  if (status.enrolled) {
    final at = status.enrolledAt;
    return at == null ? 'Ativada' : mfaEnrolledSince(at, now);
  }
  if (!status.mfaRequired) {
    // With the switch off an admin's or moderator's factor is optional
    // too, and the curation is not theirs to name.
    final staff =
        roles.contains(PlatformRole.admin) ||
        roles.contains(PlatformRole.moderator);
    return staff ? 'Opcional' : 'Opcional para a curadoria';
  }
  return roles.contains(PlatformRole.admin)
      ? 'Necessária para a administração'
      : 'Necessária para a moderação';
}

/// Whether [error] is the server saying it has no MFA key.
bool isMfaUnavailable(Object error) =>
    error is ApiError && error.code == 'mfa_unavailable';

/// What the factor is, before it is enrolled.
const mfaWhat = [
  'É um código de 6 números do app autenticador do seu celular, pedido a '
      'cada 30 minutos na administração.',
  'Você ativa uma vez: adiciona uma chave no app, digita um código e '
      'guarda seus códigos de recuperação.',
];

/// The recovery codes left.
String codesLeftWords(int n) =>
    'Códigos de recuperação: $n ${n == 1 ? 'restante' : 'restantes'}';

/// From this many codes left, the status asks for new ones.
const codesLow = 3;

/// What "Gerar novos códigos" ends.
String codesEndWords(int n) => switch (n) {
  0 => 'Você recebe 10 códigos novos.',
  1 => 'O código de agora deixa de valer.',
  _ => 'Os $n códigos de agora deixam de valer.',
};

/// What the enrolled status says to someone without the phone.
const lostDeviceLine =
    'Perdeu o celular com o app? Entre com um código de recuperação. Sem '
    'códigos, a equipe da Telinha Segura redefine a verificação para você.';

/// The notice the enrollment leaves on `/conta/verificacao`.
const mfaEnrolled = 'Verificação ativada.';
