import 'bangumi_models.dart';

class AnimeItem {
  final String id;
  final String title;
  final String subtitle;
  final String category;
  final String tag;
  final String description;
  final int colorSeed;
  final bool isPreview;
  final int? bangumiId;
  final String? posterUrl;
  final double? score;
  final int? episodeCount;
  final String? airDate;
  final List<String> tags;
  final List<String> aliases;

  const AnimeItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.tag,
    required this.description,
    required this.colorSeed,
    this.isPreview = true,
    this.bangumiId,
    this.posterUrl,
    this.score,
    this.episodeCount,
    this.airDate,
    this.tags = const [],
    this.aliases = const [],
  });

  factory AnimeItem.fromBangumi(BangumiSubject subject) {
    final tags = subject.tags.map((tag) => tag.name).toList(growable: false);
    final category = tags.isEmpty
        ? (subject.platform.isEmpty ? '番剧' : subject.platform)
        : tags.take(2).join(' / ');
    final subtitleParts = [
      if (subject.platform.isNotEmpty) subject.platform,
      if (subject.airDate.isNotEmpty) subject.airDate.split('-').first,
      if (subject.episodeCount > 0) '${subject.episodeCount} 集',
    ];
    final scoreTag = subject.ratingScore > 0
        ? '评分 ${subject.ratingScore.toStringAsFixed(1)}'
        : 'Bangumi';

    return AnimeItem(
      id: 'bangumi-${subject.id}',
      title: subject.displayName,
      subtitle: subtitleParts.join(' · '),
      category: category,
      tag: scoreTag,
      description: subject.summary.isEmpty ? '暂无简介' : subject.summary,
      colorSeed: subject.id,
      isPreview: false,
      bangumiId: subject.id,
      posterUrl: subject.largeImage,
      score: subject.ratingScore,
      episodeCount: subject.episodeCount,
      airDate: subject.airDate,
      tags: tags,
      aliases: subject.aliases,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'category': category,
    'tag': tag,
    'description': description,
    'colorSeed': colorSeed,
    'isPreview': isPreview,
    'bangumiId': bangumiId,
    'posterUrl': posterUrl,
    'score': score,
    'episodeCount': episodeCount,
    'airDate': airDate,
    'tags': tags,
    'aliases': aliases,
  };

  factory AnimeItem.fromJson(Map<String, dynamic> json) {
    return AnimeItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '未命名内容',
      subtitle: json['subtitle']?.toString() ?? '',
      category: json['category']?.toString() ?? '未分类',
      tag: json['tag']?.toString() ?? '待整理',
      description: json['description']?.toString() ?? '',
      colorSeed: (json['colorSeed'] as num?)?.toInt() ?? 0,
      isPreview: json['isPreview'] as bool? ?? false,
      bangumiId: (json['bangumiId'] as num?)?.toInt(),
      posterUrl: json['posterUrl']?.toString(),
      score: (json['score'] as num?)?.toDouble(),
      episodeCount: (json['episodeCount'] as num?)?.toInt(),
      airDate: json['airDate']?.toString(),
      tags: (json['tags'] is List)
          ? (json['tags'] as List)
                .map((tag) => tag.toString())
                .where((tag) => tag.isNotEmpty)
                .toList(growable: false)
          : const [],
      aliases: (json['aliases'] is List)
          ? (json['aliases'] as List)
                .map((alias) => alias.toString().trim())
                .where((alias) => alias.isNotEmpty)
                .toList(growable: false)
          : const [],
    );
  }
}

const previewLibrary = <AnimeItem>[
  AnimeItem(
    id: 'night-mail',
    title: '夜航邮局',
    subtitle: '把想说的话寄给下一颗星',
    category: '原创企划',
    tag: '规划中',
    description: '一个关于城市、星光和漫长旅途的本地片单预览。',
    colorSeed: 0,
  ),
  AnimeItem(
    id: 'summer-signal',
    title: '夏日信号',
    subtitle: '海风会记住每一次相遇',
    category: '青春物语',
    tag: '规划中',
    description: '用来展示卡片、收藏与详情入口的界面样例。',
    colorSeed: 1,
  ),
  AnimeItem(
    id: 'orbit-garden',
    title: '轨道花园',
    subtitle: '在失重的温室里种一场春天',
    category: '科幻',
    tag: '规划中',
    description: '内容源接入后，这里会替换为真实的内容数据。',
    colorSeed: 2,
  ),
  AnimeItem(
    id: 'paper-moon',
    title: '纸月亮放映室',
    subtitle: '每一帧都藏着一段旧梦',
    category: '短篇集',
    tag: '规划中',
    description: '本地 UI 预览内容，不包含真实播放地址。',
    colorSeed: 3,
  ),
  AnimeItem(
    id: 'blue-hour',
    title: '蓝调六点钟',
    subtitle: '太阳落山之前，故事刚刚开始',
    category: '日常',
    tag: '规划中',
    description: '当前阶段先完善浏览、收藏和日志体验。',
    colorSeed: 4,
  ),
  AnimeItem(
    id: 'wind-chimes',
    title: '风铃与远山',
    subtitle: '沿着山路去寻找夏天',
    category: '旅行',
    tag: '规划中',
    description: '当新的内容来源确定后，再接入信息获取流程。',
    colorSeed: 5,
  ),
];
