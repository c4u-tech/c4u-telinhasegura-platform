import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/curation/curation.dart';
import 'package:telinha_segura/curation/words.dart';
import 'package:telinha_segura/family/family.dart' show AgeBand;

/// No line shouts or promises.
final banned = RegExp(r'!|garantid|100\s?%', caseSensitive: false);

Review review(
  DisplayRole role,
  ReviewDecision decision, {
  VideoTheme? theme,
  AgeBand? band,
  String? reason,
}) => Review(
  displayRole: role,
  decision: decision,
  reviewedAt: DateTime.utc(2026, 10, 1),
  theme: theme,
  minAgeBand: band,
  reason: reason,
);

void main() {
  group('displayed roles, inclusive', () {
    test('each reads in PT-BR, never the wire value', () {
      expect(
        {for (final r in DisplayRole.values) r: r.label},
        {
          DisplayRole.maePai: 'Mãe ou pai',
          DisplayRole.cuidador: 'Cuidador(a)',
          DisplayRole.pedagogo: 'Pedagogo(a)',
          DisplayRole.psicologo: 'Psicólogo(a)',
          DisplayRole.educador: 'Educador(a)',
          DisplayRole.pediatra: 'Pediatra',
          DisplayRole.unknown: 'Curador(a)',
        },
      );
    });
  });

  test('themes in display order, an unknown one neutral', () {
    expect(
      [for (final t in VideoTheme.values) t.label],
      [
        'Bichos',
        'Música',
        'Histórias',
        'Aprender',
        'Brincar',
        'Natureza',
        'Tema não informado',
      ],
    );
  });

  test('bands read as the family screens read them', () {
    expect(
      [for (final b in AgeBand.values) b.label],
      ['2 a 4 anos', '5 a 8 anos', '9 a 12 anos', 'Faixa não informada'],
    );
  });

  test('a video\'s state in words', () {
    expect(
      {for (final s in VideoState.values) s: s.label},
      {
        VideoState.pending: 'Em revisão',
        VideoState.approved: 'No catálogo',
        VideoState.held: 'Fora do catálogo por enquanto',
        VideoState.removed: 'Removido',
        VideoState.unknown: 'Situação não informada',
      },
    );
  });

  test('why a video is held', () {
    expect(
      {for (final r in HeldReason.values) r: r.label},
      {
        HeldReason.review: 'Retido por recusa',
        HeldReason.reports: 'Retido por denúncias',
        HeldReason.unavailable: 'Indisponível no YouTube',
        HeldReason.doubt: 'Retido por dúvida da curadoria',
        HeldReason.audit: 'Retido pela auditoria',
        HeldReason.unknown: 'Retido',
      },
    );
  });

  test('why a family reported it', () {
    expect(
      {for (final r in ReportReason.values) r: r.label},
      {
        ReportReason.inadequado: 'Conteúdo inadequado',
        ReportReason.assustador: 'Assustador',
        ReportReason.publicidade: 'Publicidade',
        ReportReason.outro: 'Outro motivo',
        ReportReason.unknown: 'Motivo não informado',
      },
    );
  });

  group('why a suggestion was refused', () {
    test('each reason has its own calm sentence', () {
      final messages = {for (final r in RefusalReason.values) r: r.message};
      expect(messages, {
        RefusalReason.notFound:
            'Não encontramos esse vídeo no YouTube. Confira o link.',
        RefusalReason.notForKids:
            'Esse vídeo não está marcado no YouTube como feito para '
            'crianças.',
        RefusalReason.notEmbeddable:
            'O canal desse vídeo não permite que ele passe fora do YouTube.',
        RefusalReason.live:
            'Esse vídeo é uma transmissão ao vivo. Sugira um vídeo gravado.',
        RefusalReason.tooLong:
            'Esse vídeo é longo demais para o catálogo. Sugira um mais '
            'curto.',
        RefusalReason.shorts:
            'Esse link é de um Shorts. Sugira um vídeo comum do YouTube.',
        RefusalReason.removed:
            'Esse vídeo já saiu do catálogo e não pode ser sugerido de novo.',
        RefusalReason.unknown: 'Esse vídeo não pode entrar no catálogo.',
      });
      expect(messages.values.toSet(), hasLength(messages.length));
    });
  });

  group('durations in words', () {
    for (final (seconds, words) in [
      (0, 'menos de 1 min'),
      (59, 'menos de 1 min'),
      (60, '1\u00A0min'),
      (4 * 60 + 59, '4\u00A0min'),
      (59 * 60, '59\u00A0min'),
      (60 * 60, '1\u00A0h'),
      (65 * 60 + 30, '1\u00A0h\u00A005\u00A0min'),
      (130 * 60, '2\u00A0h\u00A010\u00A0min'),
    ]) {
      test('${seconds}s reads "$words", never broken at 200 % text', () {
        expect(CurationWords.duration(Duration(seconds: seconds)), words);
      });
    }
  });

  test('a dot joins words and never opens a line', () {
    expect(CurationWords.dot, '\u00A0· ');
    expect(
      CurationWords.joined(['Canal Bichos', '4\u00A0min']),
      'Canal Bichos\u00A0· 4\u00A0min',
    );
    expect(CurationWords.joined(['Só um']), 'Só um');
  });

  group('dates in words', () {
    final now = DateTime(2026, 10, 5, 15);

    test('how long ago, in calendar days on the device clock', () {
      expect(CurationWords.ago(DateTime(2026, 10, 5, 8), now), 'hoje');
      expect(CurationWords.ago(DateTime(2026, 10, 4, 23), now), 'ontem');
      expect(CurationWords.ago(DateTime(2026, 10, 2, 9), now), 'há 3 dias');
      // A clock ahead of the device's still reads today.
      expect(CurationWords.ago(DateTime(2026, 10, 6), now), 'hoje');
    });

    test('a day, with the year only when it is not this one', () {
      expect(CurationWords.date(DateTime(2026, 3, 3), now), '3 de março');
      expect(CurationWords.date(DateTime(2026, 10, 1), now), '1º de outubro');
      expect(
        CurationWords.date(DateTime(2025, 12, 31), now),
        '31 de dezembro de 2025',
      );
    });
  });

  group('a review, by displayed role, never by person', () {
    test('an approval names its theme and band', () {
      expect(
        CurationWords.review(
          review(
            DisplayRole.pedagogo,
            ReviewDecision.approve,
            theme: VideoTheme.bichos,
            band: AgeBand.from5To8,
          ),
        ),
        'Pedagogo(a) aprovou\u00A0· Bichos\u00A0· 5 a 8 anos',
      );
    });

    test('a refusal reads its decision; its reason is its own line', () {
      final r = review(
        DisplayRole.maePai,
        ReviewDecision.reject,
        reason: 'Tem um susto no fim.',
      );
      expect(CurationWords.review(r), 'Mãe ou pai recusou');
      expect(
        CurationWords.rejection(
          review(
            DisplayRole.psicologo,
            ReviewDecision.reject,
            reason: '  Tem um susto no fim. ',
          ),
        ),
        'Psicólogo(a): Tem um susto no fim.',
      );
    });

    test('unknown values stay neutral', () {
      expect(
        CurationWords.review(
          review(DisplayRole.unknown, ReviewDecision.unknown),
        ),
        'Curador(a) revisou',
      );
      expect(
        CurationWords.review(
          review(
            DisplayRole.cuidador,
            ReviewDecision.approve,
            theme: VideoTheme.unknown,
          ),
        ),
        'Cuidador(a) aprovou\u00A0· Tema não informado',
      );
    });
  });

  test('counts in words, singular and plural', () {
    expect(CurationWords.queue(1), '1 vídeo na fila');
    expect(CurationWords.queue(12), '12 vídeos na fila');
    expect(CurationWords.videos(1), '1 vídeo');
    expect(CurationWords.videos(3), '3 vídeos');
    expect(
      CurationWords.heldCounts(refusals: 2, reports: 3),
      '2 recusas\u00A0· 3 denúncias',
    );
    expect(CurationWords.heldCounts(refusals: 1, reports: 0), '1 recusa');
    expect(CurationWords.heldCounts(refusals: 0, reports: 1), '1 denúncia');
    expect(CurationWords.heldCounts(refusals: 0, reports: 0), '');
  });

  test('no line shouts or promises', () {
    final lines = [
      for (final r in DisplayRole.values) r.label,
      for (final t in VideoTheme.values) t.label,
      for (final s in VideoState.values) s.label,
      for (final r in HeldReason.values) r.label,
      for (final r in ReportReason.values) r.label,
      for (final r in RefusalReason.values) r.message,
    ];
    for (final line in lines) {
      expect(line, isNot(matches(banned)), reason: line);
    }
  });
}
