import '../curation/curation.dart';
import '../curation/family_catalog.dart';
import '../curation/words.dart';
import '../family/family.dart' show AgeBand;

/// PT-BR words for the family's catalogue screens:
/// informal "você", no exclamation marks, roles
/// in inclusive plurals, never a gender guessed for the child.

/// What a report does, said before the reasons.
const reportLead =
    'A denúncia tira este vídeo de todas as crianças da família, de vez, e '
    'o leva de volta para a curadoria.';

/// Under the primary while no reason is chosen.
const reportHint = 'Escolha um motivo acima.';

/// The done state of a new report.
const reportNew = 'Recebemos sua denúncia. O vídeo saiu dos vídeos da família.';

/// The done state when the family had already reported it.
const reportExisting = 'Sua família já tinha denunciado este vídeo.';

/// Back on the child's catalogue when a video is no longer there.
const videoGone = 'Esse vídeo saiu do catálogo.';

/// The section of today's pacotinhos on a child's catalogue, and the line
/// that closes it.
const packsHeading = 'Pacotinhos de hoje';
const packsDaily = 'Mudam a cada dia, como as prateleiras.';

/// Back on the child's catalogue when a pacotinho is not among today's.
const packGone = 'Esse pacotinho não está mais entre os de hoje.';

/// A non-breaking hyphen: "mostrá‑lo" never parts at its hyphen.
const _nbhy = '\u2011';

/// A non-breaking space: what it glues never parts at a line's end.
const _nbsp = ' ';

abstract final class CatalogWords {
  /// [n] reviewers of [role]: "1 pedagogo(a)", "2 mães ou pais", the
  /// count glued to its role.
  static String role(DisplayRole role, int n) {
    final one = n == 1;
    final words = switch (role) {
      DisplayRole.maePai => one ? 'mãe ou pai' : 'mães ou pais',
      DisplayRole.cuidador => one ? 'cuidador(a)' : 'cuidadores(as)',
      DisplayRole.pedagogo => one ? 'pedagogo(a)' : 'pedagogos(as)',
      DisplayRole.psicologo => one ? 'psicólogo(a)' : 'psicólogos(as)',
      DisplayRole.educador => one ? 'educador(a)' : 'educadores(as)',
      DisplayRole.pediatra => one ? 'pediatra' : 'pediatras',
      DisplayRole.unknown =>
        one ? 'pessoa da curadoria' : 'pessoas da curadoria',
    };
    return '$n$_nbsp$words';
  }

  /// Who approved the video, by role and never by person, and when it was
  /// last reviewed: "Revisado por 2 mães ou pais e 1 pedagogo(a) ·
  /// última revisão há 3 dias". The most frequent role first; a tie keeps
  /// the roles' own order.
  static String provenance(Provenance p, DateTime now) {
    final when = CurationWords.ago(p.lastReviewedAt, now);
    return switch (_approvers(p)) {
      final who? => CurationWords.joined([
        'Revisado por $who',
        'última revisão $when',
      ]),
      null => 'Última revisão $when',
    };
  }

  /// The approvals by role, "2 mães ou pais e 1 pedagogo(a)"; null when
  /// none is counted.
  static String? _approvers(Provenance p) {
    final counts = [
      for (final r in DisplayRole.values)
        if ((p.approvals[r] ?? 0) > 0) (r, p.approvals[r]!),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    if (counts.isEmpty) return null;
    final roles = [for (final (r, n) in counts) role(r, n)];
    return roles.length == 1
        ? roles.single
        : '${roles.sublist(0, roles.length - 1).join(', ')} e ${roles.last}';
  }

  /// A pacotinho's count and length, of the videos that play for
  /// [nickname]: "4 vídeos · 18 min", or "2 de 3 vídeos para Lia · 12 min"
  /// with one skipped.
  static String packCount(FamilyPack p, String nickname) {
    final playing = p.videos.where((v) => !v.hidden).toList();
    final total = p.videos.length;
    return CurationWords.joined([
      if (playing.length == total)
        CurationWords.videos(total)
      else
        '${playing.length} de $total vídeos para $nickname',
      CurationWords.duration(
        playing.fold(Duration.zero, (sum, v) => sum + v.duration),
      ),
    ]);
  }

  /// Who built a pacotinho and who approved it, by role and never by
  /// person, then when it was last reviewed: "Montado por
  /// pedagogo(a) · revisado por 2 mães ou pais · última revisão há 3 dias".
  static String packProvenance(FamilyPack p, DateTime now) =>
      CurationWords.joined([
        'Montado por ${p.composerRole.inline}',
        if (_approvers(p.provenance) case final who?) 'revisado por $who',
        'última revisão ${CurationWords.ago(p.provenance.lastReviewedAt, now)}',
      ]);

  /// A pacotinho's video skipped for [nickname].
  static String packSkipped(String nickname) => 'Fica de fora para $nickname';

  /// Under a pacotinho's videos: where hiding one is done.
  static String packHint(String nickname) =>
      'Para esconder um vídeo ou mostrá${_nbhy}lo de novo, abra${_nbhy}o no '
      'catálogo de $nickname.';

  /// The band as a phrase: "2 a 4 anos", "5 a 8 anos"; null when unknown.
  static String? _band(AgeBand band) => switch (band) {
    AgeBand.upTo4 => '2 a 4 anos',
    AgeBand.from5To8 => '5 a 8 anos',
    AgeBand.from9To12 => '9 a 12 anos',
    AgeBand.unknown => null,
  };

  /// A child's row on the children's list.
  static String bandRow(AgeBand band) => switch (_band(band)) {
    final b? => 'Vídeos de $b',
    null => 'Vídeos da faixa de idade da criança',
  };

  /// An empty catalogue.
  static String empty(AgeBand band) => switch (_band(band)) {
    final b? => 'Ainda não há vídeos aprovados para crianças de $b.',
    null => 'Ainda não há vídeos aprovados para a faixa de idade da criança.',
  };

  /// The catalogue's line under its title.
  static String lead(String nickname) =>
      'Tudo o que $nickname pode assistir. A cada dia, as prateleiras '
      'mostram uma parte.';

  /// The video's primary, hidden or not.
  static String hide(String nickname) => 'Esconder para $nickname';

  static String show(String nickname) => 'Mostrar para $nickname de novo';

  /// The notices once it is done.
  static String hidden(String nickname) =>
      '$nickname não vai mais ver este vídeo.';

  static String shown(String nickname) =>
      '$nickname pode ver este vídeo de novo.';

  /// The report's way back.
  static String backTo(String nickname) => 'Voltar para os vídeos de $nickname';
}
