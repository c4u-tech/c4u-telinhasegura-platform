import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/entry_screen.dart';
import 'package:telinha_segura/family/family_home_screen.dart';
import 'package:telinha_segura/access/link_account_screen.dart';
import 'package:telinha_segura/auth/provider_sign_in.dart';
import 'package:telinha_segura/design/field_layout.dart';

import 'harness.dart';
import '../design/pump.dart' show findAddress;

const signupStep = SignupRequired(ticket: 'st', email: 'ana@gmail.com');

LinkRequired linkStep(Set<LinkOption> options) =>
    LinkRequired(ticket: 'lt', email: 'ana@example.com', options: options);

Future<Harness> open(
  WidgetTester tester,
  ProviderSignInResult step,
  String path, {
  required http.Response Function(http.Request) api,
}) async {
  final h = Harness(api: api);
  h.services.pending.value = step;
  await h.pump(tester, initial: path);
  return h;
}

void main() {
  group('provider signup completion', () {
    testWidgets('shows the provider email and an unchecked declaration; '
        'confirming completes the signup', (tester) async {
      final h = await open(
        tester,
        signupStep,
        '/concluir-cadastro',
        api: (_) => json(200, {'csrf_token': 'c2'}),
      );

      expect(findAddress('ana@gmail.com'), findsOneWidget);
      expect(
        tester.widget<Text>(findAddress('ana@gmail.com')).semanticsLabel,
        'ana@gmail.com',
      );
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      final submit = find.widgetWithText(FilledButton, 'Criar conta');
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);

      h.signedIn = true;
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(
        h.actions.single,
        startsWith(
          'POST /v1/sessions/provider/signup '
          '{"ticket":"st","adult_declaration":true',
        ),
      );
      expect(h.actions.single, contains('"device_label":"$testDeviceLabel"'));
      expect(find.byType(FamilyHomeScreen), findsOneWidget);
      expect(h.services.pending.value, isNull);
    });

    testWidgets('a link_required answer moves to the link confirmation', (
      tester,
    ) async {
      await open(
        tester,
        signupStep,
        '/concluir-cadastro',
        api: (_) => problem(
          409,
          'link_required',
          extra: {
            'ticket': 'lt2',
            'email': 'ana@gmail.com',
            'options': ['password'],
          },
        ),
      );

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Criar conta'));
      await tester.pumpAndSettle();

      expect(find.byType(LinkAccountScreen), findsOneWidget);
    });
  });

  group('link confirmation', () {
    testWidgets('shows only the offered options', (tester) async {
      await open(
        tester,
        linkStep({LinkOption.password}),
        '/vincular-conta',
        api: (_) => json(200, {}),
      );

      expect(findAddress('ana@example.com'), findsOneWidget);
      expect(
        tester.widget<Text>(findAddress('ana@example.com')).semanticsLabel,
        'ana@example.com',
      );
      expect(find.widgetWithText(TextField, 'Senha'), findsOneWidget);
      expect(find.textContaining('Apagar a senha'), findsNothing);
    });

    testWidgets('the password option links with the password', (tester) async {
      final h = await open(
        tester,
        linkStep({LinkOption.password}),
        '/vincular-conta',
        api: (_) => json(200, {'csrf_token': 'c2'}),
      );
      h.signedIn = true;

      await tester.enterText(
        find.widgetWithText(TextField, 'Senha'),
        'uma senha bem comprida',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Ligar e entrar'));
      await tester.pumpAndSettle();

      expect(
        h.actions.single,
        startsWith(
          'POST /v1/sessions/provider/link '
          '{"ticket":"lt","password":"uma senha bem comprida"',
        ),
      );
      expect(h.actions.single, contains('"device_label":"$testDeviceLabel"'));
      expect(find.byType(FamilyHomeScreen), findsOneWidget);
      // "O sol sobe" greets the linked account, once.
      expect(tester.widget<FieldLayout>(find.byType(FieldLayout)).rise, isTrue);
      expect(h.services.justLinked, isFalse);
    });

    testWidgets('clearing the password names its consequence first and '
        'links clearing it', (tester) async {
      final h = await open(
        tester,
        linkStep({LinkOption.password, LinkOption.clearPassword}),
        '/vincular-conta',
        api: (_) => json(200, {'csrf_token': 'c2'}),
      );
      h.signedIn = true;

      expect(find.textContaining('todos os outros aparelhos'), findsOneWidget);
      final clear = find.widgetWithText(
        OutlinedButton,
        'Apagar a senha e ligar',
      );
      await tester.ensureVisible(clear);
      await tester.tap(clear);
      await tester.pumpAndSettle();

      expect(
        h.actions.single,
        startsWith(
          'POST /v1/sessions/provider/link '
          '{"ticket":"lt","clear_password":true',
        ),
      );
      expect(h.actions.single, contains('"device_label":"$testDeviceLabel"'));
    });

    testWidgets('a wrong password keeps the guardian here', (tester) async {
      await open(
        tester,
        linkStep({LinkOption.password}),
        '/vincular-conta',
        api: (_) => problem(401, 'invalid_credentials'),
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Senha'),
        'uma senha bem comprida',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Ligar e entrar'));
      await tester.pumpAndSettle();

      expect(find.byType(LinkAccountScreen), findsOneWidget);
      expect(find.textContaining('não conferem'), findsOneWidget);
    });

    testWidgets('an expired ticket says so and leads back to /entrar', (
      tester,
    ) async {
      await open(
        tester,
        linkStep({LinkOption.password}),
        '/vincular-conta',
        api: (_) => problem(400, 'invalid_token'),
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Senha'),
        'uma senha bem comprida',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Ligar e entrar'));
      await tester.pumpAndSettle();

      expect(find.textContaining('expirou'), findsOneWidget);
      await tester.tap(find.text('Voltar para o início'));
      await tester.pumpAndSettle();
      expect(find.byType(EntryScreen), findsOneWidget);
    });
  });
}
