/// The consent text the guardian reads before a child's profile is
/// created (Appendix, pending legal review). The app
/// sends [version] with the consent, so a change to the words is a new
/// version, here and in the backend's `family.ConsentPolicyVersion`.
abstract final class ConsentText {
  static const version = '2026-10-03';

  static const title = 'Antes de criar o perfil';

  static const paragraphs = [
    'Como responsável, você autoriza o cadastro desta criança na Telinha '
        'Segura (LGPD, art. 14).',
    'Guardamos só três coisas: o apelido que você escolher, o avatar e a '
        'faixa de idade. Nada de foto, nome completo ou data de nascimento.',
    'Esses dados servem para mostrar o perfil na sua família e para ajustar '
        'à idade da criança o que aparece para ela.',
    'Os outros adultos da sua família também veem e podem editar este '
        'perfil.',
    'Você pode excluir o perfil quando quiser. Os dados da criança são '
        'apagados na hora; guardamos apenas o registro de que você consentiu '
        'e quando, sem nenhum dado dela.',
  ];

  static const declaration =
      'Sou responsável por esta criança e autorizo o cadastro deste perfil.';
}
