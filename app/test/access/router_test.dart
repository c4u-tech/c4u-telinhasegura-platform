import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:telinha_segura/access/entry_screen.dart';
import 'package:telinha_segura/account/account_screen.dart';
import 'package:telinha_segura/account/data_screen.dart';
import 'package:telinha_segura/account/delete_account_screen.dart';
import 'package:telinha_segura/account/email_screen.dart';
import 'package:telinha_segura/account/password_screen.dart';
import 'package:telinha_segura/account/sessions_screen.dart';
import 'package:telinha_segura/family/accept_invitation_screen.dart';
import 'package:telinha_segura/family/adults_screen.dart';
import 'package:telinha_segura/family/delete_family_screen.dart';
import 'package:telinha_segura/family/family_home_screen.dart';
import 'package:telinha_segura/family/invitations_screen.dart';
import 'package:telinha_segura/access/reset_password_screen.dart';
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/auth/provider_sign_in.dart';
import 'package:telinha_segura/screentime/child_time_screen.dart';
import 'package:telinha_segura/screentime/more_time_screen.dart';
import 'package:telinha_segura/screentime/screen_time_screen.dart';
import 'package:telinha_segura/screentime/time_rules_screen.dart';
import 'package:telinha_segura/shell/splash.dart';

import '../family/fixtures.dart';
import 'harness.dart';
import '../design/pump.dart' show findAddress;

GoRouter router(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(Scaffold).first));

void main() {
  testWidgets('only a neutral splash shows while the status is unknown', (
    tester,
  ) async {
    final h = Harness(sessionDelay: const Duration(seconds: 1));
    // The first frame renders before the restore request answers.
    await tester.pumpWidget(h.app());

    expect(h.services.client.status.value, AuthStatus.unknown);
    expect(find.byType(Splash), findsOneWidget);
    expect(find.byType(EntryScreen), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(Splash), findsNothing);
    expect(find.byType(EntryScreen), findsOneWidget);
  });

  testWidgets('signed out, a signed-in route redirects to /entrar', (
    tester,
  ) async {
    await Harness().pump(tester, initial: '/');

    expect(find.byType(EntryScreen), findsOneWidget);
  });

  testWidgets('signed in, a signed-out route redirects home', (tester) async {
    await Harness(signedIn: true).pump(tester, initial: '/entrar');

    expect(find.byType(FamilyHomeScreen), findsOneWidget);
  });

  testWidgets('a status change re-routes without a restart', (tester) async {
    final h = Harness(signedIn: true);
    await h.pump(tester, initial: '/');
    expect(find.byType(FamilyHomeScreen), findsOneWidget);

    await h.services.client.forgetSession();
    await tester.pumpAndSettle();

    expect(find.byType(EntryScreen), findsOneWidget);
  });

  testWidgets('a direct URL renders its screen with its query', (tester) async {
    await Harness().pump(tester, initial: '/redefinir-senha?token=t-123');

    final screen = tester.widget<ResetPasswordScreen>(
      find.byType(ResetPasswordScreen),
    );
    expect(screen.token, 't-123');
  });

  for (final path in ['/concluir-cadastro', '/vincular-conta']) {
    testWidgets('$path without a ticket in memory goes to /entrar', (
      tester,
    ) async {
      await Harness().pump(tester, initial: path);

      expect(find.byType(EntryScreen), findsOneWidget);
    });
  }

  testWidgets('/vincular-conta with a link ticket in memory renders', (
    tester,
  ) async {
    final h = Harness();
    h.services.pending.value = const LinkRequired(
      ticket: 'tk',
      email: 'ana@example.com',
      options: {LinkOption.password},
    );
    await h.pump(tester, initial: '/vincular-conta');

    expect(find.byType(EntryScreen), findsNothing);
    expect(findAddress('ana@example.com'), findsOneWidget);
  });

  group('the invitation link', () {
    Harness invited() => Harness(
      api: (req) {
        if (req.url.path == '/v1/invitations/lookup') {
          return json(200, {
            'inviter_email': 'bia@example.com',
            'invited_email': 'ana@example.com',
            'expires_at': '2026-10-10T12:00:00Z',
          });
        }
        return json(200, {'csrf_token': 'c2'});
      },
    )..family = null;

    Future<void> signInByEmail(WidgetTester tester, Harness h) async {
      h.signedIn = true;
      await tester.enterText(
        find.widgetWithText(TextField, 'E-\u2060mail'),
        'ana@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Senha'),
        'uma senha bem comprida',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
      await tester.pumpAndSettle();
    }

    testWidgets('signed out, /convite?token=T goes to /entrar, the token '
        'held in memory only', (tester) async {
      final h = invited();
      await h.pump(tester, initial: '/convite?token=T');

      expect(find.byType(EntryScreen), findsOneWidget);
      expect(h.location(tester), '/entrar');
      expect(h.services.heldInvitation, 'T');
      expect(h.actions, isEmpty, reason: 'asked nothing signed out');
    });

    testWidgets('after signing in it returns to /convite with the token, '
        'once', (tester) async {
      final h = invited();
      await h.pump(tester, initial: '/convite?token=T');
      router(tester).go('/entrar/email');
      await tester.pumpAndSettle();

      await signInByEmail(tester, h);

      expect(find.byType(AcceptInvitationScreen), findsOneWidget);
      expect(h.location(tester), '/convite?token=T');
      expect(h.services.heldInvitation, isNull);
      expect(h.actions.last, 'POST /v1/invitations/lookup {"token":"T"}');
    });

    testWidgets('through signup and email confirmation, with no reload, '
        'the token still returns after signing in', (tester) async {
      final h = invited();
      await h.pump(tester, initial: '/convite?token=T');
      router(tester).go('/criar-conta');
      await tester.pumpAndSettle();
      router(tester).go('/verifique-seu-email', extra: 'ana@example.com');
      await tester.pumpAndSettle();
      router(tester).go('/entrar/email');
      await tester.pumpAndSettle();

      await signInByEmail(tester, h);

      expect(h.location(tester), '/convite?token=T');
    });

    testWidgets('a provider signup completion returns to /convite', (
      tester,
    ) async {
      final h = invited();
      await h.pump(tester, initial: '/convite?token=T');
      h.services.pending.value = const SignupRequired(
        ticket: 'st',
        email: 'ana@gmail.com',
      );
      router(tester).go('/concluir-cadastro');
      await tester.pumpAndSettle();
      h.signedIn = true;

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Criar conta'));
      await tester.pumpAndSettle();

      expect(h.location(tester), '/convite?token=T');
    });

    testWidgets('a linked account returns to /convite', (tester) async {
      final h = invited();
      await h.pump(tester, initial: '/convite?token=T');
      h.services.pending.value = const LinkRequired(
        ticket: 'lt',
        email: 'ana@example.com',
        options: {LinkOption.password},
      );
      router(tester).go('/vincular-conta');
      await tester.pumpAndSettle();
      h.signedIn = true;

      await tester.enterText(
        find.widgetWithText(TextField, 'Senha'),
        'uma senha bem comprida',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Ligar e entrar'));
      await tester.pumpAndSettle();

      expect(h.location(tester), '/convite?token=T');
    });

    testWidgets('signing in with nothing held lands home as before', (
      tester,
    ) async {
      final h = invited();
      await h.pump(tester, initial: '/entrar/email');

      await signInByEmail(tester, h);

      expect(h.location(tester), '/');
    });

    testWidgets('signed in, /convite renders without a detour', (tester) async {
      final h = invited()..signedIn = true;
      await h.pump(tester, initial: '/convite?token=T');

      expect(find.byType(AcceptInvitationScreen), findsOneWidget);
      expect(h.location(tester), '/convite?token=T');
      expect(h.services.heldInvitation, isNull);
    });
  });

  group('family routes', () {
    for (final path in [
      '/familia/criancas',
      '/familia/criancas/nova',
      '/familia/criancas/m1',
      '/familia/responsaveis',
      '/familia/convites',
      '/familia/excluir',
    ]) {
      testWidgets('signed out, $path redirects to /entrar', (tester) async {
        final h = Harness();
        await h.pump(tester, initial: path);

        expect(find.byType(EntryScreen), findsOneWidget);
        expect(h.location(tester), '/entrar');
      });
    }

    testWidgets('signed in, a family route renders', (tester) async {
      final h = Harness(signedIn: true)..family = ownerFamily;
      await h.pump(tester, initial: '/familia/responsaveis');

      expect(h.location(tester), '/familia/responsaveis');
    });

    for (final (path, screen) in [
      ('/familia/responsaveis', AdultsScreen),
      ('/familia/convites', InvitationsScreen),
      ('/familia/excluir', DeleteFamilyScreen),
    ]) {
      testWidgets('the owner opening $path sees its screen', (tester) async {
        final h = Harness(signedIn: true)..family = ownerFamily;
        unawaited(h.services.familyModel.load());
        await h.pump(tester, initial: path);

        expect(find.byType(screen), findsOneWidget);
      });
    }

    testWidgets('losing the family on a family screen returns home', (
      tester,
    ) async {
      final h = Harness(signedIn: true)..family = ownerFamily;
      unawaited(h.services.familyModel.load());
      await h.pump(tester, initial: '/familia/responsaveis');

      h.services.familyModel.absorb(
        const ApiError(status: 404, code: 'no_family'),
      );
      await tester.pumpAndSettle();

      expect(h.location(tester), '/');
    });

    for (final path in ['/familia/convites', '/familia/excluir']) {
      testWidgets('a guardian opening $path goes home', (tester) async {
        final h = Harness(signedIn: true)
          ..family = {...ownerFamily, 'role': 'guardian'};
        unawaited(h.services.familyModel.load());
        await h.pump(tester, initial: path);

        expect(h.location(tester), '/');
      });

      testWidgets('the owner opening $path stays', (tester) async {
        final h = Harness(signedIn: true)..family = ownerFamily;
        unawaited(h.services.familyModel.load());
        await h.pump(tester, initial: path);

        expect(h.location(tester), path);
      });
    }
  });

  group('screen-time routes', () {
    for (final (path, screen) in [
      ('/familia/tempo', ScreenTimeScreen),
      ('/familia/tempo/m1', ChildTimeScreen),
      ('/familia/tempo/m1/mais', MoreTimeScreen),
      ('/familia/tempo/m1/limite', TimeRulesScreen),
    ]) {
      for (final (role, family) in [
        ('owner', ownerFamily),
        ('guardian', {...ownerFamily, 'role': 'guardian'}),
      ]) {
        testWidgets('the $role opening $path sees its screen', (tester) async {
          final h = Harness(signedIn: true)..family = family;
          unawaited(h.services.familyModel.load());
          await h.pump(tester, initial: path);

          expect(find.byType(screen), findsOneWidget);
          expect(h.location(tester), path);
        });
      }

      testWidgets('signed out, $path redirects to /entrar', (tester) async {
        final h = Harness();
        await h.pump(tester, initial: path);

        expect(h.location(tester), '/entrar');
      });

      testWidgets('without a family, $path goes home', (tester) async {
        final h = Harness(signedIn: true)..family = null;
        await h.pump(tester, initial: path);

        expect(h.location(tester), '/');
      });
    }
  });

  group('/conta (Routes)', () {
    for (final (state, family, unverified) in [
      ('with a family', ownerFamily, false),
      ('without one', null, false),
      ('with the email unverified', null, true),
    ]) {
      testWidgets('signed in $state, it renders the account index', (
        tester,
      ) async {
        final h = Harness(signedIn: true)
          ..family = family
          ..unverified = unverified;
        await h.pump(tester, initial: '/conta');

        expect(find.byType(AccountScreen), findsOneWidget);
        expect(h.location(tester), '/conta');
      });
    }

    testWidgets('signed out, it goes to /entrar', (tester) async {
      final h = Harness();
      await h.pump(tester, initial: '/conta');

      expect(find.byType(EntryScreen), findsOneWidget);
      expect(h.location(tester), '/entrar');
    });
  });

  group('the account task routes (Routes)', () {
    for (final (path, screen) in [
      ('/conta/email', EmailScreen),
      ('/conta/senha', PasswordScreen),
      ('/conta/aparelhos', SessionsScreen),
      ('/conta/dados', DataScreen),
      ('/conta/excluir', DeleteAccountScreen),
    ]) {
      for (final (state, family, unverified) in [
        ('with a family', ownerFamily, false),
        ('without one', null, false),
        ('with the email unverified', null, true),
      ]) {
        testWidgets('$path, signed in $state, renders its screen', (
          tester,
        ) async {
          final h = Harness(signedIn: true)
            ..family = family
            ..unverified = unverified;
          await h.pump(tester, initial: path);

          expect(find.byType(screen), findsOneWidget);
          expect(h.location(tester), path);
        });
      }

      testWidgets('$path, signed out, goes to /entrar', (tester) async {
        final h = Harness();
        await h.pump(tester, initial: path);

        expect(find.byType(EntryScreen), findsOneWidget);
        expect(h.location(tester), '/entrar');
      });
    }
  });
}
