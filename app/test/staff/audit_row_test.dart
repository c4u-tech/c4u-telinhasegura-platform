import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/curation/words.dart';
import 'package:telinha_segura/design/address.dart';
import 'package:telinha_segura/staff/audit_row.dart';

import '../family/widgets_test.dart' show pumpIn;
import 'account_words_test.dart' show action;

const dot = CurationWords.dot;

void main() {
  testWidgets('the event, the subject with how, the actor line muted and '
      'the reason in quotes on its own line, read as one line, never a '
      'target', (tester) async {
    final semantics = tester.ensureSemantics();
    await withClock(Clock.fixed(DateTime(2026, 10, 8, 9)), () async {
      await pumpIn(
        tester,
        AuditActionRow(
          action(
            'account_looked_up',
            reason: 'Pedido de suporte.',
            metadata: {'by': 'email'},
          ),
        ),
      );
    });

    final lines = [
      'Conta buscada',
      'sobre ${addressBreaks('b•••@e•••.com')}${dot}por e-\u2060mail',
      '${addressBreaks('ana@example.com')}${dot}Administração$dot'
          '3 de março, 14:20',
      '“Pedido de suporte.”',
    ];
    final tops = [
      for (final line in lines) tester.getTopLeft(find.text(line)).dy,
    ];
    expect(tops, [...tops]..sort());
    expect(tops.toSet(), hasLength(4));
    expect(
      tester.getSemantics(find.byType(AuditActionRow)),
      matchesSemantics(
        label:
            'Conta buscada, sobre b•••@e•••.com${dot}por e-\u2060mail, '
            'ana@example.com${dot}Administração${dot}3 de março, 14:20, '
            '“Pedido de suporte.”',
      ),
    );
    expect(find.byType(InkWell), findsNothing);
    semantics.dispose();
  });

  testWidgets('an unknown event, an erased actor and no reason', (
    tester,
  ) async {
    await withClock(Clock.fixed(DateTime(2026, 10, 8, 9)), () async {
      await pumpIn(
        tester,
        AuditActionRow(
          action(
            'video_hidden',
            actorEmail: null,
            subjectKind: 'video',
            subjectEmail: null,
          ),
        ),
      );
    });

    expect(find.text('Outra ação da equipe'), findsOneWidget);
    expect(find.text('sobre um vídeo'), findsOneWidget);
    expect(
      find.text('conta apagada${dot}Administração${dot}3 de março, 14:20'),
      findsOneWidget,
    );
    expect(find.textContaining('“'), findsNothing);
  });
}
