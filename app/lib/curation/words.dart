import '../family/labels.dart' show AgeBandLabel;
import '../kid/theme_glyph.dart' show themeName;
import 'curation.dart';

export '../family/labels.dart' show AgeBandLabel;

/// PT-BR words for curation, as guardians, curators and the admin read
/// them: informal
/// "você", no exclamation marks, roles in inclusive labels and never the
/// wire values. A value the app does not know reads as a neutral word.
/// The bands are the family screens' own (`AgeBandLabel`), exported here.

/// How a curator's reviews and a curator are shown.
extension DisplayRoleLabel on DisplayRole {
  String get label => switch (this) {
    DisplayRole.maePai => 'Mãe ou pai',
    DisplayRole.cuidador => 'Cuidador(a)',
    DisplayRole.pedagogo => 'Pedagogo(a)',
    DisplayRole.psicologo => 'Psicólogo(a)',
    DisplayRole.educador => 'Educador(a)',
    DisplayRole.pediatra => 'Pediatra',
    DisplayRole.unknown => 'Curador(a)',
  };

  /// The same role inside a sentence: "Montado por mãe ou pai".
  String get inline => switch (this) {
    DisplayRole.maePai => 'mãe ou pai',
    DisplayRole.cuidador => 'cuidador(a)',
    DisplayRole.pedagogo => 'pedagogo(a)',
    DisplayRole.psicologo => 'psicólogo(a)',
    DisplayRole.educador => 'educador(a)',
    DisplayRole.pediatra => 'pediatra',
    DisplayRole.unknown => 'curador(a)',
  };
}

/// The themes by the names the child side gives them.
extension VideoThemeLabel on VideoTheme {
  String get label =>
      this == VideoTheme.unknown ? 'Tema não informado' : themeName(this);
}

/// Where a video, or a guardian's suggestion, stands.
extension VideoStateLabel on VideoState {
  String get label => switch (this) {
    VideoState.pending => 'Em revisão',
    VideoState.approved => 'No catálogo',
    VideoState.held => 'Fora do catálogo por enquanto',
    VideoState.removed => 'Removido',
    VideoState.unknown => 'Situação não informada',
  };
}

extension HeldReasonLabel on HeldReason {
  String get label => switch (this) {
    HeldReason.review => 'Retido por recusa',
    HeldReason.reports => 'Retido por denúncias',
    HeldReason.unavailable => 'Indisponível no YouTube',
    HeldReason.doubt => 'Retido por dúvida da curadoria',
    HeldReason.audit => 'Retido pela auditoria',
    HeldReason.unknown => 'Retido',
  };
}

extension ReportReasonLabel on ReportReason {
  String get label => switch (this) {
    ReportReason.inadequado => 'Conteúdo inadequado',
    ReportReason.assustador => 'Assustador',
    ReportReason.publicidade => 'Publicidade',
    ReportReason.outro => 'Outro motivo',
    ReportReason.unknown => 'Motivo não informado',
  };
}

/// A `video_refused` answer's reason, worded on the link field.
extension RefusalReasonMessage on RefusalReason {
  String get message => switch (this) {
    RefusalReason.notFound =>
      'Não encontramos esse vídeo no YouTube. Confira o link.',
    RefusalReason.notForKids =>
      'Esse vídeo não está marcado no YouTube como feito para crianças.',
    RefusalReason.notEmbeddable =>
      'O canal desse vídeo não permite que ele passe fora do YouTube.',
    RefusalReason.live =>
      'Esse vídeo é uma transmissão ao vivo. Sugira um vídeo gravado.',
    RefusalReason.tooLong =>
      'Esse vídeo é longo demais para o catálogo. Sugira um mais curto.',
    RefusalReason.shorts =>
      'Esse link é de um Shorts. Sugira um vídeo comum do YouTube.',
    RefusalReason.removed =>
      'Esse vídeo já saiu do catálogo e não pode ser sugerido de novo.',
    RefusalReason.unknown => 'Esse vídeo não pode entrar no catálogo.',
  };
}

/// A non-breaking space: what it glues never parts at a line's end.
const _nbsp = '\u00A0';

/// Said wherever a curator decides what refuses a video: a difference is
/// never a reason.
const differenceReminder =
    'Não recuse um vídeo só por mostrar uma família, religião, cor ou '
    'deficiência diferente da sua.';

abstract final class CurationWords {
  /// The dot between words on a line ("Canal · 4 min"), glued to the
  /// word before it so that at 200 % text it never opens a line.
  static const dot = '$_nbsp· ';

  /// [parts] joined by [dot].
  static String joined(Iterable<String> parts) => parts.join(dot);

  /// A video's length, rounded down to the minute: "menos de 1 min",
  /// "4 min", "1 h", "1 h 05 min", every inner space non-breaking so a
  /// length never parts across lines.
  static String duration(Duration d) {
    final minutes = d.inMinutes;
    if (minutes < 1) return 'menos de 1 min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '$m${_nbsp}min';
    if (m == 0) return '$h${_nbsp}h';
    return '$h${_nbsp}h$_nbsp${m.toString().padLeft(2, '0')}${_nbsp}min';
  }

  /// How long ago, in calendar days on the device clock: "hoje",
  /// "ontem", "há 3 dias". A time ahead of [now] still reads "hoje".
  static String ago(DateTime at, DateTime now) {
    final local = at.toLocal();
    final here = now.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    final today = DateTime(here.year, here.month, here.day);
    // Rounded: a daylight-saving day is 23 or 25 hours long.
    final days = (today.difference(day).inHours / 24).round();
    return switch (days) {
      <= 0 => 'hoje',
      1 => 'ontem',
      _ => 'há $days dias',
    };
  }

  static const _months = [
    'janeiro',
    'fevereiro',
    'março',
    'abril',
    'maio',
    'junho',
    'julho',
    'agosto',
    'setembro',
    'outubro',
    'novembro',
    'dezembro',
  ];

  /// A local day: "3 de março", "1º de outubro", with the year only when
  /// it is not [now]'s ("31 de dezembro de 2025"), or [always].
  static String date(DateTime at, DateTime now, {bool always = false}) {
    final local = at.toLocal();
    final day = local.day == 1 ? '1º' : '${local.day}';
    final year = !always && local.year == now.toLocal().year
        ? ''
        : ' de ${local.year}';
    return '$day de ${_months[local.month - 1]}$year';
  }

  /// One review of the round, by displayed role: "Pedagogo(a)
  /// aprovou · Bichos · 5 a 8 anos", "Mãe ou pai recusou", "Educador(a)
  /// teve dúvida · Música · 2 a 4 anos". A refusal's or a doubt's reason is
  /// its own line.
  static String review(Review r) {
    final who = r.displayRole.label;
    return switch (r.decision) {
      ReviewDecision.approve => [
        '$who aprovou',
        ?r.theme?.label,
        ?r.minAgeBand?.label,
      ].join(dot),
      ReviewDecision.reject => '$who recusou',
      ReviewDecision.doubt => [
        '$who teve dúvida',
        ?r.theme?.label,
        ?r.minAgeBand?.label,
      ].join(dot),
      ReviewDecision.unknown => '$who revisou',
    };
  }

  /// What a review marked, question by question in the list's order:
  /// "Aparece: Alguém bate…", "Tenho dúvida: Ritmo calmo?". Nothing for a
  /// review with every answer "ok" or none at all.
  static List<String> marked(Review r, Checklist list) => [
    for (final item in list.items)
      if (r.answers?[item.id] case final a?
          when a != ChecklistAnswer.ok && a != ChecklistAnswer.unknown)
        '${a.label(item)}: ${item.text}',
  ];

  /// A held video's refusal: "Psicólogo(a): Tem um susto no fim."
  static String rejection(Review r) {
    final reason = r.reason?.trim() ?? '';
    final who = r.displayRole.label;
    return reason.isEmpty ? who : '$who: $reason';
  }

  /// The curator's door: "12 vídeos na fila".
  static String queue(int n) =>
      n == 1 ? '1 vídeo na fila' : '$n vídeos na fila';

  /// The admin's door: "3 vídeos".
  static String videos(int n) => n == 1 ? '1 vídeo' : '$n vídeos';

  /// A held row's counts: "2 recusas · 3 denúncias", leaving out a zero.
  static String heldCounts({required int refusals, required int reports}) => [
    if (refusals > 0) refusals == 1 ? '1 recusa' : '$refusals recusas',
    if (reports > 0) reports == 1 ? '1 denúncia' : '$reports denúncias',
  ].join(dot);
}

/// A mark on a question, in words: "Aparece", "Não" (a question asked in
/// the positive), "Tenho dúvida".
extension ChecklistMarkLabel on ChecklistAnswer {
  String label(ChecklistItem item) => switch (this) {
    ChecklistAnswer.appears => item.positive ? 'Não' : 'Aparece',
    ChecklistAnswer.doubt => 'Tenho dúvida',
    ChecklistAnswer.ok => item.positive ? 'Sim' : 'Não aparece',
    ChecklistAnswer.unknown => 'Sem resposta',
  };
}

/// An answer in words. Every question asks whether something is in the
/// video, so "Não" is always the answer that keeps it.
extension ChecklistAnswerWord on ChecklistAnswer {
  String get word => switch (this) {
    ChecklistAnswer.ok => 'Não',
    ChecklistAnswer.appears => 'Sim',
    ChecklistAnswer.doubt => 'Não sei',
    ChecklistAnswer.unknown => 'Sem resposta',
  };
}
