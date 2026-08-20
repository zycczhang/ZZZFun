class BangumiTag {
  final String name;
  final int count;

  const BangumiTag({required this.name, required this.count});

  factory BangumiTag.fromJson(Map<String, dynamic> json) {
    return BangumiTag(
      name: json['name']?.toString().trim() ?? '',
      count: _asInt(json['count']),
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'count': count};
}

class BangumiSubject {
  final int id;
  final int type;
  final String platform;
  final String name;
  final String nameCn;
  final String summary;
  final String airDate;
  final int episodeCount;
  final Map<String, String> images;
  final List<BangumiTag> tags;
  final List<String> aliases;
  final double ratingScore;
  final int ratingRank;
  final int ratingVotes;

  const BangumiSubject({
    required this.id,
    required this.type,
    required this.platform,
    required this.name,
    required this.nameCn,
    required this.summary,
    required this.airDate,
    required this.episodeCount,
    required this.images,
    required this.tags,
    required this.aliases,
    required this.ratingScore,
    required this.ratingRank,
    required this.ratingVotes,
  });

  String get displayName => nameCn.isNotEmpty ? nameCn : name;

  String? get largeImage {
    final value = _firstNonEmpty([
      images['large'],
      images['common'],
      images['medium'],
      images['small'],
    ]);
    if (value == null) return null;
    return value.startsWith('http://')
        ? 'https://${value.substring('http://'.length)}'
        : value;
  }

  factory BangumiSubject.fromJson(Map<String, dynamic> json) {
    final rating = _asMap(json['rating']);
    final imageMap = _asStringMap(json['images']);
    final fallbackImage = json['image']?.toString().trim() ?? '';
    final rawNameCn = json['name_cn'] ?? json['nameCN'];
    final rawAirDate = json['date'] ?? json['air_date'];
    final rawSummary = json['summary'] ?? json['info'];
    final parsedAirDate = rawAirDate?.toString().trim() ?? '';
    final episodeCount = _asInt(json['eps']);
    if (fallbackImage.isNotEmpty && !imageMap.containsKey('large')) {
      imageMap['large'] = fallbackImage;
    }

    return BangumiSubject(
      id: _asInt(json['id']),
      type: _asInt(json['type']),
      platform: json['platform']?.toString().trim() ?? '',
      name: json['name']?.toString().trim() ?? '',
      nameCn: rawNameCn?.toString().trim() ?? '',
      summary: rawSummary?.toString().trim() ?? '',
      airDate: parsedAirDate.isNotEmpty
          ? parsedAirDate
          : _airDateFromInfo(json['info']),
      episodeCount: episodeCount > 0
          ? episodeCount
          : _episodeCountFromInfo(json['info']),
      images: imageMap,
      tags: _parseTags(json['tags'] ?? json['metaTags']),
      aliases: _parseAliases(json['infobox']),
      ratingScore: _asDouble(rating['score']),
      ratingRank: _asInt(rating['rank']),
      ratingVotes: _asInt(rating['total']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'platform': platform,
    'name': name,
    'name_cn': nameCn,
    'summary': summary,
    'date': airDate,
    'eps': episodeCount,
    'images': images,
    'tags': tags.map((tag) => tag.toJson()).toList(),
    'aliases': aliases,
    'rating': {'score': ratingScore, 'rank': ratingRank, 'total': ratingVotes},
  };
}

class BangumiEpisode {
  final int id;
  final num sort;
  final int type;
  final String name;
  final String nameCn;
  final String airDate;
  final String duration;

  const BangumiEpisode({
    required this.id,
    required this.sort,
    required this.type,
    required this.name,
    required this.nameCn,
    required this.airDate,
    required this.duration,
  });

  String get displayName => nameCn.isNotEmpty ? nameCn : name;

  factory BangumiEpisode.fromJson(Map<String, dynamic> json) {
    return BangumiEpisode(
      id: _asInt(json['id']),
      sort: json['sort'] is num ? json['sort'] as num : _asInt(json['sort']),
      type: _asInt(json['type']),
      name: json['name']?.toString().trim() ?? '',
      nameCn: json['name_cn']?.toString().trim() ?? '',
      airDate: json['airdate']?.toString().trim() ?? '',
      duration: json['duration']?.toString().trim() ?? '',
    );
  }
}

class BangumiCalendarDay {
  final int weekdayId;
  final String weekdayCn;
  final String weekdayEn;
  final List<BangumiSubject> subjects;

  const BangumiCalendarDay({
    required this.weekdayId,
    required this.weekdayCn,
    required this.weekdayEn,
    required this.subjects,
  });

  factory BangumiCalendarDay.fromJson(Map<String, dynamic> json) {
    final weekday = _asMap(json['weekday']);
    return BangumiCalendarDay(
      weekdayId: _asInt(weekday['id']),
      weekdayCn: weekday['cn']?.toString().trim() ?? '',
      weekdayEn: weekday['en']?.toString().trim() ?? '',
      subjects: _asList(json['items'])
          .map(BangumiSubject.fromJson)
          .where((subject) => subject.id > 0)
          .toList(growable: false),
    );
  }
}

class BangumiSearchPage {
  final List<BangumiSubject> subjects;
  final int total;

  const BangumiSearchPage({required this.subjects, required this.total});
}

List<Map<String, dynamic>> _asList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is! Map) return <String, dynamic>{};
  return Map<String, dynamic>.from(value);
}

Map<String, String> _asStringMap(Object? value) {
  if (value is! Map) return <String, String>{};
  return value.map(
    (key, item) => MapEntry(key.toString(), item?.toString() ?? ''),
  );
}

List<String> _parseAliases(Object? value) {
  final infobox = _asList(value);
  for (final item in infobox) {
    if (item['key']?.toString() != '别名') continue;
    final raw = item['values'] ?? item['value'];
    if (raw is List) {
      return raw
          .map((alias) {
            if (alias is Map && alias['v'] != null) {
              return alias['v'].toString().trim();
            }
            return alias.toString().trim();
          })
          .where((alias) => alias.isNotEmpty)
          .toList(growable: false);
    }
    final alias = raw?.toString().trim() ?? '';
    return alias.isEmpty ? const [] : [alias];
  }
  return const [];
}

List<BangumiTag> _parseTags(Object? value) {
  if (value is! List) return const [];
  return value
      .map((item) {
        if (item is Map) {
          return BangumiTag.fromJson(Map<String, dynamic>.from(item));
        }
        return BangumiTag(name: item.toString().trim(), count: 0);
      })
      .where((tag) => tag.name.isNotEmpty)
      .toList(growable: false);
}

int _asInt(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int _episodeCountFromInfo(Object? value) {
  final match = RegExp(r'(\d+)\s*话').firstMatch(value?.toString() ?? '');
  return int.tryParse(match?.group(1) ?? '') ?? 0;
}

String _airDateFromInfo(Object? value) {
  final match = RegExp(r'(\d{4})年(\d{1,2})月(\d{1,2})日')
      .firstMatch(value?.toString() ?? '');
  if (match == null) return '';

  final year = match.group(1)!;
  final month = match.group(2)!.padLeft(2, '0');
  final day = match.group(3)!.padLeft(2, '0');
  return '$year-$month-$day';
}

String? _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    if (value != null && value.trim().isNotEmpty) return value;
  }
  return null;
}
