import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/family/family.dart';
import 'package:telinha_segura/family/labels.dart';

void main() {
  test('each age band has its PT-BR label, unknown a neutral one', () {
    expect(AgeBand.upTo4.label, '2 a 4 anos');
    expect(AgeBand.from5To8.label, '5 a 8 anos');
    expect(AgeBand.from9To12.label, '9 a 12 anos');
    expect(AgeBand.unknown.label, 'Faixa não informada');
  });

  test('each avatar is named by its animal', () {
    expect(
      {for (final a in Avatar.values) a: a.label},
      {
        Avatar.fox: 'raposa',
        Avatar.owl: 'coruja',
        Avatar.cat: 'gato',
        Avatar.dog: 'cachorro',
        Avatar.rabbit: 'coelho',
        Avatar.bear: 'urso',
        Avatar.turtle: 'tartaruga',
        Avatar.whale: 'baleia',
        Avatar.lion: 'leão',
        Avatar.panda: 'panda',
        Avatar.frog: 'sapo',
        Avatar.penguin: 'pinguim',
        Avatar.unknown: 'avatar não informado',
      },
    );
  });

  test('the capacity words state the count out of the family limits', () {
    expect(FamilyWords.children(2), '2 de 10 crianças');
    expect(FamilyWords.children(1), '1 de 10 crianças');
  });

  test('the adults capacity counts places, naming adults and invitations '
      'apart when some wait', () {
    expect(FamilyWords.adults(3, 0), '3 de 6 vagas');
    expect(FamilyWords.adults(3, 1), '4 de 6 vagas: 3 adultos e 1 convite');
    expect(FamilyWords.adults(1, 2), '3 de 6 vagas: 1 adulto e 2 convites');
  });

  test('the pending invitations count agrees in number', () {
    expect(
      FamilyWords.invitationsWaiting(0),
      'Nenhum convite esperando resposta',
    );
    expect(FamilyWords.invitationsWaiting(1), '1 convite esperando resposta');
    expect(FamilyWords.invitationsWaiting(2), '2 convites esperando resposta');
  });

  test('an invitation\'s expiry counts calendar days, calmly', () {
    final now = DateTime(2026, 10, 3, 22, 30);
    expect(FamilyWords.expiry(DateTime(2026, 10, 3, 23), now), 'expira hoje');
    expect(FamilyWords.expiry(DateTime(2026, 10, 4, 1), now), 'expira amanhã');
    expect(
      FamilyWords.expiry(DateTime(2026, 10, 8, 9), now),
      'expira em 5 dias',
    );
    expect(
      FamilyWords.expiry(DateTime(2026, 10, 3, 20), now),
      'expira hoje',
      reason: 'past but still listed: the server decides',
    );
  });

  test('the expiry reads the wire\'s UTC time in local days', () {
    final expires = DateTime.utc(2026, 10, 10, 12);
    final local = expires.toLocal();
    final now = DateTime(local.year, local.month, local.day - 7, 8);
    expect(FamilyWords.expiry(expires, now), 'expira em 7 dias');
  });

  test('names join as PT-BR lists them', () {
    expect(FamilyWords.names(['Lia']), 'Lia');
    expect(FamilyWords.names(['Lia', 'Téo']), 'Lia e Téo');
    expect(FamilyWords.names(['Lia', 'Téo', 'Nina']), 'Lia, Téo e Nina');
  });
}
