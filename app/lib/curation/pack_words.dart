import 'curation.dart';
import 'pack.dart';
import 'words.dart';

/// PT-BR words for the pacotinhos' curation,
/// in the voice of the curation screens' words.
abstract final class PackWords {
  /// Where a pacotinho stands, for the caller: what they may review
  /// first, then the state. The admin's reads are never reviewable, so
  /// they read the state alone.
  static String state(Pack p) => switch (p.state) {
    PackState.approved when p.reviewable => 'Nova versão para você revisar',
    _ when p.reviewable => 'Para você revisar',
    PackState.pending => 'Em revisão',
    PackState.approved => 'Publicado',
    PackState.held => 'Recusado',
    PackState.removed => 'Removido',
    PackState.unknown => 'Situação não informada',
  };

  /// A pacotinho's row: "4 vídeos · 18 min · Música", the theme when set.
  static String meta(Pack p) => CurationWords.joined([
    CurationWords.videos(p.videos.length),
    CurationWords.duration(p.total),
    ?p.theme?.label,
  ]);

  /// The admin's door: "8 pacotinhos", or "Mais de 50 pacotinhos" when
  /// the first page has more.
  static String count(int n, {required bool more}) => more
      ? 'Mais de $n pacotinhos'
      : n == 1
      ? '1 pacotinho'
      : '$n pacotinhos';

  /// One review of the round by displayed role: "Pedagogo(a) aprovou",
  /// "Mãe ou pai recusou"; a refusal's reason is its own line.
  static String review(PackReview r) {
    final who = r.displayRole.label;
    return switch (r.decision) {
      ReviewDecision.approve => '$who aprovou',
      ReviewDecision.reject => '$who recusou',
      ReviewDecision.doubt => '$who teve dúvida',
      ReviewDecision.unknown => '$who revisou',
    };
  }
}
