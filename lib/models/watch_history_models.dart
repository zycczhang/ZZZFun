import 'anime_models.dart';
import 'video_source_models.dart';

class WatchHistoryEntry {
  final AnimeItem item;
  final String sourceSite;
  final String sourceLine;
  final int sourceIndex;
  final String searchItemName;
  final String searchItemSource;
  final String episodeName;
  final int episodeIndex;
  final String episodeUrl;
  final int positionMs;
  final int durationMs;

  const WatchHistoryEntry({
    required this.item,
    this.sourceSite = '',
    this.sourceLine = '',
    this.sourceIndex = -1,
    this.searchItemName = '',
    this.searchItemSource = '',
    this.episodeName = '',
    this.episodeIndex = -1,
    this.episodeUrl = '',
    this.positionMs = 0,
    this.durationMs = 0,
  });

  factory WatchHistoryEntry.fromSelection({
    required AnimeItem item,
    required VideoPlaybackSelection selection,
    Duration position = Duration.zero,
    Duration duration = Duration.zero,
  }) {
    final sourceIndex = _sourceIndexFor(selection);
    final source =
        sourceIndex >= 0 && sourceIndex < selection.chapters.sources.length
        ? selection.chapters.sources[sourceIndex]
        : null;
    return WatchHistoryEntry(
      item: item,
      sourceSite: selection.rule.name,
      sourceLine: source?.name ?? '',
      sourceIndex: sourceIndex,
      searchItemName: selection.searchItem.name,
      searchItemSource: selection.searchItem.source,
      episodeName: selection.episode.name,
      episodeIndex: selection.episode.episodeIndex,
      episodeUrl: selection.episode.pageUrl,
      positionMs: position.inMilliseconds.clamp(0, 0x7fffffffffffffff),
      durationMs: duration.inMilliseconds.clamp(0, 0x7fffffffffffffff),
    );
  }

  factory WatchHistoryEntry.fromJson(Map<String, dynamic> json) {
    final rawItem = json['item'];
    final item = rawItem is Map
        ? AnimeItem.fromJson(Map<String, dynamic>.from(rawItem))
        : AnimeItem.fromJson(json);
    return WatchHistoryEntry(
      item: item,
      sourceSite: json['sourceSite']?.toString() ?? '',
      sourceLine: json['sourceLine']?.toString() ?? '',
      sourceIndex: _asInt(json['sourceIndex'], fallback: -1),
      searchItemName: json['searchItemName']?.toString() ?? '',
      searchItemSource: json['searchItemSource']?.toString() ?? '',
      episodeName: json['episodeName']?.toString() ?? '',
      episodeIndex: _asInt(json['episodeIndex'], fallback: -1),
      episodeUrl: json['episodeUrl']?.toString() ?? '',
      positionMs: _asInt(json['positionMs']),
      durationMs: _asInt(json['durationMs']),
    );
  }

  bool get hasPlaybackSelection =>
      sourceSite.isNotEmpty &&
      searchItemSource.isNotEmpty &&
      episodeUrl.isNotEmpty;

  Duration get position => Duration(milliseconds: positionMs);

  String get episodeLabel {
    if (episodeName.isNotEmpty) return episodeName;
    if (episodeIndex >= 0) return '第${episodeIndex + 1}集';
    return '未知集数';
  }

  String get positionLabel {
    final totalSeconds = positionMs ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds ~/ 60)
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  String get displaySummary {
    if (!hasPlaybackSelection) return '尚未开始播放';
    final line = sourceLine.isEmpty ? '默认线路' : sourceLine;
    return '$sourceSite · $line\n$episodeLabel · $positionLabel';
  }

  Map<String, dynamic> toJson() => {
    'item': item.toJson(),
    'sourceSite': sourceSite,
    'sourceLine': sourceLine,
    'sourceIndex': sourceIndex,
    'searchItemName': searchItemName,
    'searchItemSource': searchItemSource,
    'episodeName': episodeName,
    'episodeIndex': episodeIndex,
    'episodeUrl': episodeUrl,
    'positionMs': positionMs,
    'durationMs': durationMs,
  };
}

int _sourceIndexFor(VideoPlaybackSelection selection) {
  final episode = selection.episode;
  if (episode.roadIndex >= 0 &&
      episode.roadIndex < selection.chapters.sources.length &&
      selection.chapters.sources[episode.roadIndex].episodes.any(
        (candidate) =>
            candidate.pageUrl == episode.pageUrl &&
            candidate.name == episode.name,
      )) {
    return episode.roadIndex;
  }
  final exactIndex = selection.chapters.sources.indexWhere(
    (source) => source.episodes.any(
      (candidate) =>
          candidate.pageUrl == episode.pageUrl &&
          candidate.name == episode.name,
    ),
  );
  if (exactIndex >= 0) return exactIndex;
  return -1;
}

int _asInt(Object? value, {int fallback = 0}) {
  final parsed = value is num
      ? value.toInt()
      : int.tryParse(value?.toString() ?? '');
  return parsed == null || parsed < 0 ? fallback : parsed;
}
