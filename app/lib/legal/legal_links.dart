import 'package:flutter/material.dart';

import '../access/widgets.dart';
import '../design/tokens.dart';
import '../shell/services.dart';

/// The version of the terms of use and the privacy policy the app shows.
/// A sign-up and an acceptance send it, and the server refuses any other
/// than its own `identity.TermsVersion`: a change to either page that
/// matters to users bumps both.
const kTermsVersion = '2026-10-17';

final kTermsUrl = Uri.parse('https://telinhasegura.coding4u.tech/termos');
final kPrivacyUrl = Uri.parse(
  'https://telinhasegura.coding4u.tech/privacidade',
);

const termsLabel = 'Termos de uso';
const privacyLabel = 'Política de privacidade';

/// What creating an account agrees to, under the adult declaration.
const signupAgreement =
    'Ao criar a conta, você concorda com os Termos de uso e com a Política '
    'de privacidade.';

/// The terms of use and the privacy policy, each a whole-width link of
/// its own that opens the site outside the app.
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key});

  @override
  Widget build(BuildContext context) {
    final links = AppScope.of(context).links;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          link: true,
          child: QuietAction(
            label: termsLabel,
            onPressed: () => links.open(kTermsUrl),
          ),
        ),
        Semantics(
          link: true,
          child: QuietAction(
            label: privacyLabel,
            onPressed: () => links.open(kPrivacyUrl),
          ),
        ),
      ],
    );
  }
}

/// The sign-up's agreement sentence, then the two pages it names.
class SignupAgreement extends StatelessWidget {
  const SignupAgreement({super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(signupAgreement, style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: Space.xs),
      const LegalLinks(),
    ],
  );
}
