import 'package:flutter/material.dart';

import '../access/widgets.dart';
import '../design/tokens.dart';
import '../shell/services.dart';

/// The consent text the guardian reads before a child's profile is
/// created, and again to authorize an existing profile under new terms.
/// The app sends [version] with the consent, so a change to the words is
/// a new version, here and in the backend's `family.ConsentPolicyVersion`.
abstract final class ConsentText {
  static const version = '2026-10-17';

  static const title = 'Antes de criar o perfil';

  static const paragraphs = [
    'Como mãe, pai ou responsável legal, você autoriza o cadastro desta '
        'criança no Telinha Segura (LGPD, art. 14).',
    'Guardamos o apelido que você escolher, o avatar e a faixa de idade. '
        'Nada de foto, nome completo ou data de nascimento.',
    'Guardamos também o que a criança assiste: qual vídeo, em qual '
        'aparelho, quando e por quanto tempo. Isso conta o tempo de tela e '
        'mostra a você os últimos dias. Cada vídeo assistido é apagado '
        'depois de 30 dias; os totais de tempo por dia, depois de 90.',
    'Esses dados servem para mostrar o perfil na sua família, ajustar à '
        'idade da criança o que aparece para ela e cuidar do tempo de tela.',
    'Os outros adultos da sua família também veem e podem editar este '
        'perfil.',
    'Você não é obrigado a autorizar. Sem a autorização, o perfil não é '
        'criado e o modo criança não funciona para esta criança; sua conta '
        'continua funcionando.',
    'Você pode excluir o perfil quando quiser. Os dados da criança são '
        'apagados na hora; guardamos apenas o registro de que você '
        'consentiu e quando, sem nenhum dado dela. Saiba mais na Política '
        'de privacidade.',
  ];

  static const declaration =
      'Sou mãe, pai ou responsável legal por esta criança e autorizo o '
      'cadastro deste perfil.';

  /// The same text for a profile that already exists, under its own
  /// heading and declaration.
  static const reconsentTitle = 'Autorize de novo';

  static const reconsentDeclaration =
      'Sou mãe, pai ou responsável legal por esta criança e autorizo o '
      'perfil com estas informações.';

  /// The policy the last paragraph names, opened outside the app.
  static const privacyLabel = 'Política de privacidade';

  static final privacyUrl = Uri.parse(
    'https://telinhasegura.coding4u.tech/privacidade',
  );
}

/// The consent text under [title], paragraph by paragraph, then the
/// privacy policy the last paragraph names, as a link of its own: a
/// whole-width target rather than a few words inside a sentence.
class ConsentTextBlock extends StatelessWidget {
  const ConsentTextBlock({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text(title, style: text.titleMedium)),
        const SizedBox(height: Space.md),
        for (final paragraph in ConsentText.paragraphs) ...[
          Text(paragraph, style: text.bodyLarge),
          const SizedBox(height: Space.md),
        ],
        Semantics(
          link: true,
          child: QuietAction(
            label: ConsentText.privacyLabel,
            onPressed: () =>
                AppScope.of(context).links.open(ConsentText.privacyUrl),
          ),
        ),
      ],
    );
  }
}
