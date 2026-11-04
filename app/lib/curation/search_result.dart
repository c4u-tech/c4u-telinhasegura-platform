/// One hit of a guardian's title search: the video as YouTube lists it, and
/// whether it can be suggested. A hit that cannot be carries the [refusal]
/// reason; one already in the catalogue carries its [state].
class SearchResult {
  const SearchResult({
    required this.youtubeId,
    required this.title,
    required this.channelTitle,
    required this.durationSeconds,
    required this.suggestible,
    this.refusal,
    this.state,
  });

  factory SearchResult.fromJson(Map<String, dynamic> j) => SearchResult(
    youtubeId: j['youtube_id'] as String,
    title: j['title'] as String,
    channelTitle: j['channel_title'] as String,
    durationSeconds: j['duration_seconds'] as int,
    suggestible: j['suggestible'] as bool,
    refusal: j['refusal'] as String?,
    state: j['state'] as String?,
  );

  final String youtubeId;
  final String title;
  final String channelTitle;
  final int durationSeconds;
  final bool suggestible;
  final String? refusal;
  final String? state;
}
