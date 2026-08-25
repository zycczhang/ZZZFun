import 'kazumi_rule_models.dart';

class VideoSearchItem {
  final String name;
  final String source;
  final String ruleName;

  const VideoSearchItem({
    required this.name,
    required this.source,
    required this.ruleName,
  });
}

enum VideoRuleSearchStatus { pending, success, noResult, error, unsupported }

class VideoRuleSearchResult {
  final String ruleName;
  final VideoRuleSearchStatus status;
  final List<VideoSearchItem> items;
  final String? message;

  const VideoRuleSearchResult({
    required this.ruleName,
    required this.status,
    this.items = const [],
    this.message,
  });

  VideoRuleSearchResult copyWith({
    VideoRuleSearchStatus? status,
    List<VideoSearchItem>? items,
    String? message,
  }) => VideoRuleSearchResult(
    ruleName: ruleName,
    status: status ?? this.status,
    items: items ?? this.items,
    message: message ?? this.message,
  );
}

class VideoEpisode {
  final String name;
  final String pageUrl;
  final int roadIndex;
  final int episodeIndex;
  final Map<String, String> requestHeaders;
  final Map<String, String> mediaHeaders;
  final bool useLegacyParser;

  const VideoEpisode({
    required this.name,
    required this.pageUrl,
    required this.roadIndex,
    required this.episodeIndex,
    this.requestHeaders = const {},
    this.mediaHeaders = const {},
    this.useLegacyParser = false,
  });
}

class VideoSource {
  final String name;
  final List<VideoEpisode> episodes;

  const VideoSource({required this.name, required this.episodes});
}

class VideoChapterResult {
  final String ruleName;
  final String source;
  final List<VideoSource> sources;

  const VideoChapterResult({
    required this.ruleName,
    required this.source,
    required this.sources,
  });
}

class VideoPlaybackSelection {
  final KazumiRule rule;
  final VideoSearchItem searchItem;
  final VideoChapterResult chapters;
  final VideoEpisode episode;

  const VideoPlaybackSelection({
    required this.rule,
    required this.searchItem,
    required this.chapters,
    required this.episode,
  });
}
