import '../auth/api_error.dart';

/// PT-BR copy for the access screens: informal "você", sentence case, calm,
/// no exclamation marks, no guarantees (scanned by
/// copy_test.dart). Screens switch on `ApiError.code` only.
///
/// In this copy and every screen's, "e-mail" carries a word joiner
/// (U+2060) after its hyphen, so a narrow line never breaks the word;
/// Bricolage Grotesque has no non-breaking hyphen (U+2011) glyph.
abstract final class Copy {
  static const genericRetry =
      'Não conseguimos falar com o servidor agora. Confira sua conexão e '
      'tente de novo.';

  static const passwordGuidance = 'Use pelo menos 15 caracteres.';

  /// Re-authentication with a Google or Apple login that is not this
  /// account's (the API answers `invalid_credentials`).
  static const otherProviderAccount =
      'Esse login não está ligado a esta conta. Use o login da sua conta, '
      'ou sua senha.';

  /// The children's `limit_reached`, and the hint under a full family's
  /// "Cadastrar criança". The family holds 10 children.
  static const childrenFull = 'A família já tem 10 crianças, o máximo.';

  /// The adults' `limit_reached`, and the hint under a full family's
  /// "Enviar convite". Pending invitations take a place.
  static const adultsFull =
      'A família já tem 6 adultos, contando os convites pendentes.';

  /// A child's `not_found`: the list comes back refreshed.
  static const childGone =
      'Esse perfil não existe mais. Atualizamos a lista para você.';

  /// An invitation's `invalid_token`, or a link without its token:
  /// nothing more is said about it.
  static const invitationGone =
      'Este convite expirou ou já foi usado. Peça um convite novo para a '
      'pessoa titular da família.';

  /// An invitation's `limit_reached`, worded for the invited adult.
  static const invitationFamilyFull =
      'Essa família já está completa, com 6 adultos. Fale com a pessoa '
      'titular da família.';

  /// The PIN's rule, for a PIN the server answers `validation` to.
  static const pinRule = 'Use de 4 a 6 números.';

  /// A link code's `invalid_token`: unknown, expired or
  /// used, which the app cannot tell apart.
  static const linkCodeGone =
      'Esse código está errado ou já expirou. Gere um código novo no '
      'aparelho do adulto e digite de novo.';

  /// The devices' `limit_reached`.
  static const devicesFull =
      'A família já tem 10\u00A0aparelhos vinculados, o máximo. Para vincular '
      'outro, desvincule um deles.';

  /// A new link code's `limit_reached` while the family has room for
  /// devices: 5 codes are already waiting.
  static const linkCodesFull =
      'Já há 5\u00A0códigos esperando para ser usados. Use um deles, ou '
      'espere um expirar, em até 10\u00A0minutos, e gere outro.';

  /// The entry screen's notice after an unlock that ended the session: the
  /// guardian's family went while the device was in kid mode .
  static const familyGone =
      'O modo criança terminou porque esta família não existe mais. Entre '
      'de novo para continuar.';

  /// A new email's `validation`: the server answers alike
  /// for an invalid address and for the account's current one.
  static const newEmailInvalid =
      'Digite um e-\u2060mail válido e diferente do atual.';

  /// A password change's `invalid_credentials`: only the
  /// current password can be wrong there.
  static const currentPasswordWrong =
      'A senha atual não confere. Confira e tente de novo.';

  /// Ending a session another device already ended (`not_found`):
  /// the list is read again.
  static const sessionGone =
      'Esse aparelho já tinha saído da sua conta. Atualizamos a lista para '
      'você.';

  /// The overrides of the link-code screens: generating and redeeming.
  static const linkCode = {
    'invalid_token': linkCodeGone,
    'limit_reached': devicesFull,
  };

  static const _byCode = {
    'invalid_credentials':
        'O e-\u2060mail ou a senha não conferem. Confira e tente de novo.',
    'validation': 'Confira os campos e tente de novo.',
    'invalid_token': 'Este passo expirou. Comece de novo.',
    'unauthenticated': 'Sua sessão terminou. Entre de novo.',
    'identity_conflict':
        'Essa conta já tem outro login desse provedor ligado a ela. Entre '
        'com ele, ou com seu e-\u2060mail e senha.',
    'provider_email_unverified':
        'O e-\u2060mail dessa conta ainda não foi confirmado pelo provedor. '
        'Confirme por lá, ou entre com e-\u2060mail e senha.',
    // Family codes. limit_reached is generic here: the screens word it for
    // children or adults.
    'email_unverified':
        'Confirme seu e-\u2060mail antes de cuidar da família. Enviamos o link '
        'quando você criou a conta.',
    'already_in_family':
        'Sua conta já faz parte de uma família. Para entrar em outra, saia '
        'dela primeiro.',
    'no_family': 'Você não faz mais parte desta família.',
    'not_owner': 'Só a pessoa titular da família pode fazer isso.',
    'owner_must_transfer':
        'Antes de sair, passe a titularidade para outro responsável.',
    'limit_reached': 'A família já está completa.',
    'policy_outdated':
        'O texto de consentimento mudou. Para continuar, atualize o app. O '
        'que você preencheu continua aqui.',
    'invitation_email_mismatch':
        'Este convite foi enviado para outro e-\u2060mail. Entre com a conta '
        'desse e-\u2060mail para aceitar.',
    // An invitation the app offered that is gone: the same words as a
    // spent link.
    'invitation_unavailable': invitationGone,
    'already_member': 'Essa pessoa já faz parte da sua família.',
    'not_found': 'Isso não existe mais. Atualizamos a lista para você.',
    'reauth_required': 'Para continuar, confirme que é você.',
    // Parental codes. invalid_token and limit_reached keep
    // the generic words above: the link-code screens override them.
    'pin_not_set':
        'A família ainda não tem PIN. Crie o PIN em Modo criança para '
        'começar.',
    'invalid_pin': 'PIN errado. Tente de novo.',
    'weak_pin':
        'Esse PIN é fácil de adivinhar. Evite números repetidos ou em '
        'sequência, como 1111 ou 1234.',
    'kid_mode':
        'Este aparelho está no modo criança. Para sair, use o PIN dos pais.',
    'not_child': 'Este aparelho não está mais no modo criança.',
    'profile_gone':
        'O perfil desta criança não existe mais. Um adulto pode sair do modo '
        'criança com o PIN.',
    // An app older than the terms the server holds.
    'terms_outdated': 'Os termos mudaram. Atualize o app para continuar.',
    // A child's profile waiting for a guardian to authorize it again.
    'consent_required':
        'Este perfil precisa de uma nova autorização de um adulto.',
    // Screen-time codes. The child never reads
    // time_up: the child home shows the sleeping telinha instead.
    'over_cap': 'Hoje já chega a 4 horas, o máximo.',
    'time_up':
        'Agora não é hora de assistir: o tempo de hoje acabou ou está fora '
        'do horário.',
    // Platform roles: the area's door goes too.
    'not_curator': 'Você não faz mais parte da curadoria.',
    'not_admin': 'Você não tem mais acesso à administração.',
    'not_moderator': 'Você não tem mais acesso à moderação.',
    // The curation checklist, the curator terms and the audits.
    'checklist_outdated':
        'A lista de perguntas mudou. Abrimos a nova para você responder.',
    'checklist_refuses':
        'Com o que você marcou, o vídeo não pode ser aprovado. Recuse '
        'marcando o que aparece.',
    'checklist_band':
        'Com o ritmo que você marcou, o vídeo não serve para 2 a 4 anos. '
        'Escolha outra idade.',
    'conflict_of_interest':
        'Você tem vínculo com este canal, então a revisão dele fica com '
        'outros curadores.',
    'declaration_required': 'Para revisar, aceite antes o termo do curador.',
    'declaration_outdated':
        'O termo do curador mudou. Leia a versão nova para aceitar.',
    'already_audited': 'Essa aprovação já foi conferida.',
    'own_review':
        'Você revisou este vídeo nesta rodada; outra pessoa da equipe precisa '
        'decidir.',
  };

  static const _weakPassword = {
    'breached':
        'Essa senha apareceu em um vazamento conhecido de dados. Escolha '
        'outra.',
    'too_short': 'A senha precisa ter pelo menos 15 caracteres.',
    'too_long': 'A senha pode ter no máximo 128 caracteres.',
  };

  /// The message for [error]. [overrides] lets a screen word a code for
  /// its own context, such as an expired link versus an expired ticket.
  static String forError(
    Object error, {
    Map<String, String> overrides = const {},
  }) {
    if (error is! ApiError) return genericRetry;
    final override = overrides[error.code];
    if (override != null) return override;
    if (error.code == 'weak_password') {
      for (final reason in ['breached', 'too_short', 'too_long']) {
        if (error.reasons.contains(reason)) return _weakPassword[reason]!;
      }
      return _weakPassword['too_short']!;
    }
    if (error.code == 'rate_limited') {
      return retryIn(error.retryAfter ?? const Duration(seconds: 60));
    }
    return _byCode[error.code] ?? genericRetry;
  }

  static String retryIn(Duration wait) {
    final minutes = wait.inMinutes;
    final seconds = wait.inSeconds % 60;
    final left = minutes == 0
        ? '$seconds s'
        : seconds == 0
        ? '$minutes min'
        : '$minutes min $seconds s';
    return 'Muitas tentativas seguidas. Você pode tentar de novo em $left.';
  }
}
