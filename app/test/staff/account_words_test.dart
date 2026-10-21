import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/curation/words.dart';
import 'package:telinha_segura/staff/account_words.dart';
import 'package:telinha_segura/staff/accounts.dart';

const dot = CurationWords.dot;
final now = DateTime(2026, 10, 8, 9);

AuditAction action(
  String event, {
  String? actorEmail = 'ana@example.com',
  String actorRole = 'admin',
  String? subjectKind = 'account',
  String? subjectEmail = 'b•••@e•••.com',
  String? reason,
  Map<String, String> metadata = const {},
}) => AuditAction(
  id: 1,
  occurredAt: DateTime(2026, 3, 3, 14, 20),
  event: event,
  actorId: 'a1',
  actorEmail: actorEmail,
  actorRole: actorRole,
  subjectKind: subjectKind,
  subjectId: subjectKind == null ? null : 's1',
  subjectEmailMasked: subjectEmail,
  reason: reason,
  metadata: metadata,
);

void main() {
  group('figures', () {
    test('thousands take a "."', () {
      expect(AccountWords.figure(0, suppressedBelow: 5), '0');
      expect(AccountWords.figure(999, suppressedBelow: 5), '999');
      expect(AccountWords.figure(1240, suppressedBelow: 5), '1.240');
      expect(AccountWords.figure(1234567, suppressedBelow: 5), '1.234.567');
    });

    test('a suppressed count reads "menos de 5", and the line says so', () {
      expect(AccountWords.figure(null, suppressedBelow: 5), 'menos de 5');
      expect(
        AccountWords.suppression(5),
        'Números abaixo de 5 aparecem como “menos de 5”.',
      );
    });
  });

  test('a moment reads "3 de março, 14:20", the year only when not this '
      'one\'s', () {
    expect(
      AccountWords.moment(DateTime(2026, 3, 3, 14, 20), now),
      '3 de março, 14:20',
    );
    expect(
      AccountWords.moment(DateTime(2025, 12, 31, 8, 5), now),
      '31 de dezembro de 2025, 08:05',
    );
  });

  group('event words', () {
    test('every staff event the server records, in words', () {
      expect(
        {
          for (final e in [
            'account_looked_up',
            'account_sessions_revoked',
            'account_device_unlinked',
            'account_password_reset_sent',
            'curator_appointed',
            'curator_updated',
            'curator_removed',
            'moderator_appointed',
            'moderator_removed',
            'video_removed',
            'video_reopened',
            'pack_removed',
            'admin_granted',
            'admin_revoked',
            'mfa_reset',
            'account_suspended',
            'account_reinstated',
            'video_doubt_decided',
            'approval_audited',
          ])
            e: AccountWords.event(e),
        },
        {
          'account_looked_up': 'Conta buscada',
          'account_sessions_revoked': 'Sessões encerradas',
          'account_device_unlinked': 'Aparelho desvinculado',
          'account_password_reset_sent': 'Redefinição de senha enviada',
          'curator_appointed': 'Nomeação para a curadoria',
          'curator_updated': 'Mudança na curadoria',
          'curator_removed': 'Saída da curadoria',
          'moderator_appointed': 'Nomeação para a moderação',
          'moderator_removed': 'Saída da moderação',
          'video_removed': 'Vídeo removido de vez',
          'video_reopened': 'Vídeo reaberto para revisão',
          'pack_removed': 'Pacotinho removido de vez',
          'admin_granted': 'Administração concedida',
          'admin_revoked': 'Administração retirada',
          'mfa_reset': 'Verificação em duas etapas redefinida',
          'account_suspended': 'Conta suspensa',
          'account_reinstated': 'Conta reativada',
          'video_doubt_decided': 'Dúvida da curadoria decidida',
          'approval_audited': 'Aprovação conferida',
        },
      );
    });

    test('anything else reads "Outra ação da equipe"', () {
      expect(AccountWords.event('video_hidden'), 'Outra ação da equipe');
      expect(AccountWords.event(''), 'Outra ação da equipe');
    });
  });

  group('the subject', () {
    test('an account by its masked email, or erased', () {
      expect(
        AccountWords.subject(action('account_looked_up')),
        'sobre b•••@e•••.com',
      );
      expect(
        AccountWords.subject(action('mfa_reset', subjectEmail: null)),
        'sobre uma conta apagada',
      );
    });

    test('a video, a pacotinho', () {
      expect(
        AccountWords.subject(
          action('video_removed', subjectKind: 'video', subjectEmail: null),
        ),
        'sobre um vídeo',
      );
      expect(
        AccountWords.subject(
          action('pack_removed', subjectKind: 'pack', subjectEmail: null),
        ),
        'sobre um pacotinho',
      );
    });

    test('a lookup that missed reads "nenhuma conta encontrada"', () {
      expect(
        AccountWords.subject(
          action(
            'account_looked_up',
            subjectKind: null,
            subjectEmail: null,
            metadata: {'by': 'email', 'match': 'none'},
          ),
        ),
        'nenhuma conta encontrada',
      );
    });

    test('no subject, no line', () {
      expect(
        AccountWords.subject(
          action('admin_granted', subjectKind: null, subjectEmail: null),
        ),
        isNull,
      );
    });

    test('the address goes through the given function', () {
      expect(
        AccountWords.subject(
          action('account_looked_up'),
          address: (a) => '<$a>',
        ),
        'sobre <b•••@e•••.com>',
      );
    });
  });

  group('from the metadata only how and how many', () {
    test('"por e-mail", "por código"', () {
      expect(
        AccountWords.details(
          action('account_looked_up', metadata: {'by': 'email'}),
        ),
        ['por e-\u2060mail'],
      );
      expect(
        AccountWords.details(
          action('account_looked_up', metadata: {'by': 'id', 'match': 'none'}),
        ),
        ['por código'],
      );
    });

    test('"3 sessões", "1 sessão"', () {
      expect(
        AccountWords.details(
          action('account_sessions_revoked', metadata: {'sessions': '3'}),
        ),
        ['3 sessões'],
      );
      expect(
        AccountWords.details(
          action('account_sessions_revoked', metadata: {'sessions': '1'}),
        ),
        ['1 sessão'],
      );
    });

    test('nothing else the metadata holds', () {
      expect(
        AccountWords.details(
          action(
            'curator_appointed',
            metadata: {'display_role': 'pedagogo', 'sessions': 'x'},
          ),
        ),
        isEmpty,
      );
    });
  });

  group('the actor line', () {
    test('the email, the role in words and the moment', () {
      expect(
        AccountWords.actor(action('account_looked_up'), now),
        'ana@example.com${dot}Administração${dot}3 de março, 14:20',
      );
      expect(
        AccountWords.actor(
          action('video_removed', actorRole: 'moderator'),
          now,
        ),
        'ana@example.com${dot}Moderação${dot}3 de março, 14:20',
      );
    });

    test('an erased actor reads "conta apagada"; an unknown role is left '
        'out', () {
      expect(
        AccountWords.actor(
          action('account_looked_up', actorEmail: null, actorRole: 'auditor'),
          now,
        ),
        'conta apagada${dot}3 de março, 14:20',
      );
    });
  });

  test('the reason in quotes, absent when blank', () {
    expect(
      AccountWords.reason(action('x', reason: 'Pedido de suporte.')),
      '“Pedido de suporte.”',
    );
    expect(AccountWords.reason(action('x')), isNull);
    expect(AccountWords.reason(action('x', reason: '  ')), isNull);
  });

  group('the sheet', () {
    test('how the account signs in, in the order held, an unknown way left '
        'out', () {
      expect(
        AccountWords.providers(['password', 'google', 'apple']),
        'Entra com Senha${dot}Google${dot}Apple',
      );
      expect(AccountWords.providers(['google']), 'Entra com Google');
      expect(
        AccountWords.providers(['passkey', 'password']),
        'Entra com Senha',
      );
      expect(AccountWords.providers([]), isNull);
      expect(AccountWords.providers(['passkey']), isNull);
    });

    test('when it was made, always with the year', () {
      expect(
        AccountWords.created(DateTime(2026, 3, 3, 14)),
        'Conta criada em 3 de março de 2026',
      );
      expect(
        AccountWords.created(DateTime(2025, 10, 1, 14)),
        'Conta criada em 1º de outubro de 2025',
      );
    });

    test('a suspension: since a local day and time, always with the year', () {
      expect(
        AccountWords.suspendedSince(DateTime(2026, 10, 8, 14, 20)),
        'Suspensa desde 8 de outubro de 2026, 14:20',
      );
      expect(
        AccountWords.suspendedSince(DateTime(2025, 1, 1, 8, 5)),
        'Suspensa desde 1º de janeiro de 2025, 08:05',
      );
    });

    test('the family: the role, then the counts, never a name', () {
      expect(AccountWords.familyRole('owner'), 'Responsável principal');
      expect(AccountWords.familyRole('guardian'), 'Responsável');
      expect(
        AccountWords.familyCounts(
          const SheetFamily(role: 'owner', minors: 2, devices: 1),
        ),
        '2 crianças${dot}1 aparelho ativo',
      );
      expect(
        AccountWords.familyCounts(
          const SheetFamily(role: 'guardian', minors: 1, devices: 0),
        ),
        '1 criança${dot}0 aparelhos ativos',
      );
      expect(
        AccountWords.familyCounts(
          const SheetFamily(role: 'guardian', minors: 0, devices: 3),
        ),
        '0 crianças${dot}3 aparelhos ativos',
      );
    });

    test('a device: linked at a moment, seen in days', () {
      expect(
        AccountWords.linked(DateTime(2026, 3, 3, 14, 20), now),
        'Vinculado em 3 de março, 14:20',
      );
      expect(
        AccountWords.seen(DateTime(2026, 10, 6, 23), now),
        'Visto há 2 dias',
      );
      expect(AccountWords.seen(DateTime(2026, 10, 7, 9), now), 'Visto ontem');
      expect(AccountWords.seen(DateTime(2026, 10, 8, 8), now), 'Visto hoje');
    });

    test('a session: the client as "Aparelhos conectados" names it, when '
        'it began and its last use', () {
      expect(AccountWords.client('web'), 'Navegador');
      expect(AccountWords.client('mobile'), 'Celular ou tablet');
      expect(
        AccountWords.started(DateTime(2026, 3, 3, 14), now),
        'entrou em 3 de março',
      );
    });
  });
}
