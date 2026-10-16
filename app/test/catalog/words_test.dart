import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/catalog/words.dart';
import 'package:telinha_segura/curation/curation.dart';
import 'package:telinha_segura/curation/family_catalog.dart';
import 'package:telinha_segura/family/family.dart' show AgeBand;

import '../curation/words_test.dart' show banned;

/// [s] with the Whole Phrase Rule's non-breaking spaces made plain.
String plain(String s) => s.replaceAll(' ', ' ');

final now = DateTime.utc(2026, 10, 6, 15);

Provenance provenance(Map<DisplayRole, int> approvals, {int daysAgo = 3}) =>
    Provenance(
      approvals: approvals,
      lastReviewedAt: now.subtract(Duration(days: daysAgo)),
    );

/// A pacotinho of [videos] as (seconds, hidden), composed by a
/// pedagogue and approved as [approvals] say.
FamilyPack pack(
  List<(int, bool)> videos, {
  Map<DisplayRole, int> approvals = const {DisplayRole.maePai: 2},
}) => FamilyPack(
  id: 'k1',
  title: 'Bichos da fazenda',
  coverVideoId: 'p1',
  composerRole: DisplayRole.pedagogo,
  videos: [
    for (final (i, (seconds, hidden)) in videos.indexed)
      FamilyPackVideo(
        id: 'p$i',
        title: 'Vídeo $i',
        duration: Duration(seconds: seconds),
        hidden: hidden,
      ),
  ],
  provenance: provenance(approvals),
);

void main() {
  group('a pacotinho (pacotinhos in the guardian\'s catalogue)', () {
    test('its count and length, of what plays', () {
      expect(
        plain(
          CatalogWords.packCount(
            pack([(240, false), (360, false), (300, false), (180, false)]),
            'Lia',
          ),
        ),
        '4 vídeos · 18 min',
      );
    });

    test('with a video skipped, how many of all play for the child, and '
        'only their length', () {
      expect(
        plain(
          CatalogWords.packCount(
            pack([(300, false), (240, true), (420, false)]),
            'Lia',
          ),
        ),
        '2 de 3 vídeos para Lia · 12 min',
      );
    });

    test('who built it, who approved it by role and when', () {
      expect(
        plain(
          CatalogWords.packProvenance(
            pack(
              [(240, false), (240, false), (240, false)],
              approvals: {DisplayRole.pedagogo: 1, DisplayRole.maePai: 2},
            ),
            now,
          ),
        ),
        'Montado por pedagogo(a) · revisado por 2 mães ou pais e 1 '
        'pedagogo(a) · última revisão há 3 dias',
      );
    });

    test('with no approval counted, who built it and when', () {
      expect(
        plain(
          CatalogWords.packProvenance(
            pack([(240, false), (240, false), (240, false)], approvals: {}),
            now,
          ),
        ),
        'Montado por pedagogo(a) · última revisão há 3 dias',
      );
    });

    test('a skipped video and the way to hide one', () {
      expect(CatalogWords.packSkipped('Lia'), 'Fica de fora para Lia');
      expect(
        CatalogWords.packHint('Lia'),
        'Para esconder um vídeo ou mostrá\u2011lo de novo, abra\u2011o no '
        'catálogo de Lia.',
      );
    });
  });

  group('the provenance sentence', () {
    test('counts by role in inclusive plurals, most frequent first, '
        'joined with "e", then the last review in words', () {
      expect(
        plain(
          CatalogWords.provenance(
            provenance({DisplayRole.pedagogo: 1, DisplayRole.maePai: 2}),
            now,
          ),
        ),
        'Revisado por 2 mães ou pais e 1 pedagogo(a) · última revisão há 3 '
        'dias',
      );
    });

    test('three roles or more: commas, then "e" before the last', () {
      expect(
        plain(
          CatalogWords.provenance(
            provenance({
              DisplayRole.cuidador: 1,
              DisplayRole.psicologo: 2,
              DisplayRole.maePai: 1,
            }, daysAgo: 0),
            now,
          ),
        ),
        'Revisado por 2 psicólogos(as), 1 mãe ou pai e 1 cuidador(a) · '
        'última revisão hoje',
      );
    });

    test('every role has its singular and its plural', () {
      expect(
        {
          for (final r in DisplayRole.values)
            r: (plain(CatalogWords.role(r, 1)), plain(CatalogWords.role(r, 2))),
        },
        {
          DisplayRole.maePai: ('1 mãe ou pai', '2 mães ou pais'),
          DisplayRole.cuidador: ('1 cuidador(a)', '2 cuidadores(as)'),
          DisplayRole.pedagogo: ('1 pedagogo(a)', '2 pedagogos(as)'),
          DisplayRole.psicologo: ('1 psicólogo(a)', '2 psicólogos(as)'),
          DisplayRole.educador: ('1 educador(a)', '2 educadores(as)'),
          DisplayRole.pediatra: ('1 pediatra', '2 pediatras'),
          DisplayRole.unknown: (
            '1 pessoa da curadoria',
            '2 pessoas da curadoria',
          ),
        },
      );
    });

    test('a count never parts from its role, nor the dot from the words '
        'before it (the Whole Phrase Rule)', () {
      final s = CatalogWords.provenance(
        provenance({DisplayRole.maePai: 2}, daysAgo: 1),
        now,
      );
      expect(s, contains('2 mães'));
      expect(s, contains('pais · '));
      expect(plain(s), endsWith('última revisão ontem'));
    });

    test('roles with no approval are left out; with none at all, only the '
        'last review', () {
      expect(
        plain(
          CatalogWords.provenance(
            provenance({DisplayRole.maePai: 1, DisplayRole.pediatra: 0}),
            now,
          ),
        ),
        'Revisado por 1 mãe ou pai · última revisão há 3 dias',
      );
      expect(
        plain(CatalogWords.provenance(provenance({}), now)),
        'Última revisão há 3 dias',
      );
    });
  });

  group('a child\'s band in words', () {
    test('the children\'s rows and the empty catalogue', () {
      expect(
        {for (final b in AgeBand.values) b: CatalogWords.bandRow(b)},
        {
          AgeBand.upTo4: 'Vídeos de até 4 anos',
          AgeBand.from5To8: 'Vídeos de 5 a 8 anos',
          AgeBand.from9To12: 'Vídeos de 9 a 12 anos',
          AgeBand.unknown: 'Vídeos da faixa de idade da criança',
        },
      );
      expect(
        CatalogWords.empty(AgeBand.from5To8),
        'Ainda não há vídeos aprovados para crianças de 5 a 8 anos.',
      );
      expect(
        CatalogWords.empty(AgeBand.unknown),
        'Ainda não há vídeos aprovados para a faixa de idade da criança.',
      );
    });
  });

  test('no line shouts or promises, and none guesses a gender', () {
    final lines = [
      CatalogWords.lead('Lia'),
      CatalogWords.hidden('Lia'),
      CatalogWords.shown('Lia'),
      CatalogWords.hide('Lia'),
      CatalogWords.show('Lia'),
      CatalogWords.backTo('Lia'),
      reportLead,
      reportHint,
      reportNew,
      reportExisting,
      videoGone,
      packsHeading,
      packsDaily,
      packGone,
      CatalogWords.packSkipped('Lia'),
      CatalogWords.packHint('Lia'),
      for (final b in AgeBand.values) CatalogWords.empty(b),
    ];
    for (final l in lines) {
      expect(l, isNot(matches(banned)), reason: l);
      expect(l, isNot(matches(RegExp(r'\bdel[ae]\b|\bel[ae]\b'))), reason: l);
    }
  });
}
