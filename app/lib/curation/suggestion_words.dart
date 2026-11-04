/// The words of the suggestion screen and its confirmation: PT-BR,
/// informal "você", no exclamation marks.
library;

import 'package:flutter/widgets.dart';

/// Under the primary while the field is empty (disabled with a hint).
const emptyHint = 'Busque pelo título ou cole o link de um vídeo do YouTube.';

/// Under the primary while the words are too few to search.
const shortHint = 'Digite pelo menos 2 letras.';

/// Under the primary while the words are too many to search.
const longHint = 'Use até 100 caracteres.';

/// The fewest and most characters a search takes, its inner spaces
/// collapsed, as the server counts them.
const searchMin = 2;
const searchMax = 100;

/// `invalid_link` (and `validation`), on the field.
const invalidLink = 'Esse link não é de um vídeo do YouTube.';

/// `video_source_unavailable`: YouTube did not answer the server.
const sourceUnavailable =
    'Não conseguimos consultar o YouTube agora. Tente de novo em alguns '
    'minutos.';

/// `search_unavailable` with a wait: the day's searches are spent. No
/// countdown, since the wait runs to the next day; a link still works.
const searchDaily =
    'A busca está indisponível por hoje. Cole o link do vídeo para sugerir.';

/// `search_unavailable` without a wait: YouTube failed this once.
const searchNow =
    'Não conseguimos buscar no YouTube agora. Tente de novo ou cole o link.';

/// After "Colar link" found no YouTube link to paste.
const noClipboardLink = 'A área de transferência não tem um link do YouTube.';

/// From this text scale the screen makes room for words: "Colar link"
/// stands under the field, and result rows drop their thumbnail so titles
/// take the whole column.
const largeTextFrom = 1.5;

/// Whether the text scale in force is [largeTextFrom] or more.
bool largeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1) >= largeTextFrom;
