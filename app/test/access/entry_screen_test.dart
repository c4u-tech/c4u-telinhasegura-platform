import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/entry_screen.dart';
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/family/family_home_screen.dart';
import 'package:telinha_segura/access/link_account_screen.dart';
import 'package:telinha_segura/access/provider_signup_screen.dart';
import 'package:telinha_segura/auth/provider_sign_in.dart';
import 'package:telinha_segura/design/field_layout.dart';

import '../parental/fakes.dart';
import 'harness.dart';
import '../design/pump.dart' show findAddress;

http.Response Function(http.Request) providerAnswers(http.Response answer) =>
    (req) => req.url.path == '/v1/sessions/provider'
    ? answer
    : http.Response('', 204);

void main() {
  testWidgets('entry shows the promise, both providers, email and signup', (
    tester,
  ) async {
    await Harness(settings: allProviders).pump(tester, initial: '/entrar');

    expect(find.text(promiseLine), findsOneWidget);
    expect(find.text('Continuar com o Google'), findsOneWidget);
    expect(find.text('Continuar com a Apple'), findsOneWidget);
    expect(find.text('Entrar com e-\u2060mail'), findsOneWidget);
    expect(find.text('Criar conta'), findsOneWidget);
  });

  testWidgets('providers without settings are not offered', (tester) async {
    await Harness().pump(tester, initial: '/entrar');

    expect(find.text('Continuar com o Google'), findsNothing);
    expect(find.text('Continuar com a Apple'), findsNothing);
    expect(find.text('Entrar com e-\u2060mail'), findsOneWidget);
  });

  testWidgets('a provider token is offered to the API', (tester) async {
    final h = Harness(
      settings: allProviders,
      api: providerAnswers(json(200, {'csrf_token': 'c2'})),
    );
    h.providers.answers[IdentityProvider.apple] = 'apple-id-token';
    await h.pump(tester, initial: '/entrar');
    h.signedIn = true;

    await tester.tap(find.text('Continuar com a Apple'));
    await tester.pumpAndSettle();

    expect(h.providers.asked, [IdentityProvider.apple]);
    final body = jsonDecode(h.actions.single.split(' ').skip(2).join(' '));
    expect(body['provider'], 'apple');
    expect(body['id_token'], 'apple-id-token');
    expect(body['device_label'], testDeviceLabel);
    expect(find.byType(FamilyHomeScreen), findsOneWidget);
  });

  testWidgets('a cancelled provider sheet returns to idle silently', (
    tester,
  ) async {
    final h = Harness(settings: allProviders);
    h.providers.answers[IdentityProvider.google] = null;
    await h.pump(tester, initial: '/entrar');

    await tester.tap(find.text('Continuar com o Google'));
    await tester.pumpAndSettle();

    expect(h.actions, isEmpty);
    expect(find.byType(EntryScreen), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
  });

  testWidgets('signup_required leads to the signup completion', (tester) async {
    final h = Harness(
      settings: allProviders,
      api: providerAnswers(
        problem(
          409,
          'signup_required',
          extra: {'ticket': 'tk', 'email': 'ana@gmail.com'},
        ),
      ),
    );
    h.providers.answers[IdentityProvider.google] = 'g-token';
    await h.pump(tester, initial: '/entrar');

    await tester.tap(find.text('Continuar com o Google'));
    await tester.pumpAndSettle();

    expect(find.byType(ProviderSignupScreen), findsOneWidget);
    expect(findAddress('ana@gmail.com'), findsOneWidget);
  });

  testWidgets('link_required leads to the link confirmation', (tester) async {
    final h = Harness(
      settings: allProviders,
      api: providerAnswers(
        problem(
          409,
          'link_required',
          extra: {
            'ticket': 'tk',
            'email': 'ana@example.com',
            'options': ['password'],
          },
        ),
      ),
    );
    h.providers.answers[IdentityProvider.google] = 'g-token';
    await h.pump(tester, initial: '/entrar');

    await tester.tap(find.text('Continuar com o Google'));
    await tester.pumpAndSettle();

    expect(find.byType(LinkAccountScreen), findsOneWidget);
  });

  for (final code in ['identity_conflict', 'provider_email_unverified']) {
    testWidgets('$code is explained and the guardian stays', (tester) async {
      final h = Harness(
        settings: allProviders,
        api: providerAnswers(problem(409, code)),
      );
      h.providers.answers[IdentityProvider.google] = 'g-token';
      await h.pump(tester, initial: '/entrar');

      await tester.tap(find.text('Continuar com o Google'));
      await tester.pumpAndSettle();

      expect(find.byType(EntryScreen), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });
  }

  testWidgets('on the web, Google renders its own button and the screen owns '
      'its token stream', (tester) async {
    final google = FakeGoogleWeb();
    final h = Harness(
      settings: allProviders,
      googleWeb: google,
      api: providerAnswers(json(200, {'csrf_token': 'c2'})),
    );
    await h.pump(tester, initial: '/entrar');

    expect(find.byKey(const Key('gis-button')), findsOneWidget);
    expect(find.text('Continuar com o Google'), findsNothing);
    expect(google.tokens.hasListener, isTrue);

    h.signedIn = true;
    google.tokens.add('gis-token');
    await tester.pumpAndSettle();

    expect(h.actions.single, contains('"id_token":"gis-token"'));
    expect(find.byType(FamilyHomeScreen), findsOneWidget);
    expect(google.tokens.hasListener, isFalse);
  });

  group('"Este aparelho é de uma criança"', () {
    const offer = 'Este aparelho é de uma criança';

    testWidgets(
      'on Android and iOS it opens /vincular-aparelho',
      (tester) async {
        final h = Harness(
          kind: ClientKind.mobile,
          devices: MemoryDeviceCredentialStore(),
        );
        await h.pump(tester, initial: '/entrar');

        await tester.ensureVisible(find.text(offer));
        await tester.tap(find.text(offer));
        await tester.pumpAndSettle();

        expect(h.location(tester), '/vincular-aparelho');
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );

    testWidgets('the web does not offer it', (tester) async {
      // The web keeps no device credential: main gives it no store.
      await Harness(settings: allProviders).pump(tester, initial: '/entrar');

      expect(find.text(offer), findsNothing);
    });

    testWidgets('a desktop does not offer it', (tester) async {
      await Harness(
        kind: ClientKind.mobile,
        devices: MemoryDeviceCredentialStore(),
      ).pump(tester, initial: '/entrar');

      expect(find.text(offer), findsNothing);
    }, variant: TargetPlatformVariant.desktop());
  });
}
