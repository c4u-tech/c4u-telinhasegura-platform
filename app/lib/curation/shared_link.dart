/// The hosts a shared video link may come from.
const _youtubeHosts = {
  'youtu.be',
  'youtube.com',
  'www.youtube.com',
  'm.youtube.com',
};

/// The longest shared text read; anything longer is not a share from the
/// YouTube app.
const _maxSharedText = 2048;

final _urlPattern = RegExp(r'https?://\S+', caseSensitive: false);

/// The first YouTube link in [text], as shared from another app, without
/// the `si` tracking parameter; null when there is none.
String? youtubeLinkIn(String? text) {
  if (text == null || text.length > _maxSharedText) return null;
  for (final match in _urlPattern.allMatches(text)) {
    final uri = Uri.tryParse(match.group(0)!);
    if (uri == null ||
        !_youtubeHosts.contains(uri.host.toLowerCase()) ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasFragment) {
      continue;
    }
    final params = {...uri.queryParametersAll}..remove('si');
    // `replace` keeps the old query when given none, so drop it explicitly.
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      path: uri.path,
      queryParameters: params.isEmpty ? null : params,
    ).toString();
  }
  return null;
}
