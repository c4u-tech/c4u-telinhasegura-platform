import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/family/consent.dart';
import 'package:telinha_segura/family/family.dart';

void main() {
  test('the text carries the version the app sends', () {
    // The app never records consent against a text it did not show.
    expect(ConsentText.version, kConsentPolicyVersion);
    expect(ConsentText.version, '2026-10-17');
  });

  test('the text says what is kept, why, for how long, and that the '
      'guardian may refuse', () {
    expect(ConsentText.title, 'Antes de criar o perfil');
    expect(ConsentText.paragraphs, [
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
    ]);
    expect(
      ConsentText.declaration,
      'Sou mãe, pai ou responsável legal por esta criança e autorizo o '
      'cadastro deste perfil.',
    );
  });

  test('the last paragraph points to the privacy policy', () {
    expect(ConsentText.paragraphs.last, contains(ConsentText.privacyLabel));
    expect(ConsentText.privacyLabel, 'Política de privacidade');
    expect(
      ConsentText.privacyUrl,
      Uri.parse('https://telinhasegura.coding4u.tech/privacidade'),
    );
  });

  test('an existing profile is authorized again under its own words', () {
    expect(ConsentText.reconsentTitle, 'Autorize de novo');
    expect(
      ConsentText.reconsentDeclaration,
      'Sou mãe, pai ou responsável legal por esta criança e autorizo o '
      'perfil com estas informações.',
    );
  });
}
