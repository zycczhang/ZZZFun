import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/bangumi_models.dart';
import 'app_logger.dart';

class BangumiApiException implements Exception {
  final String message;
  final int? statusCode;
  final Object? cause;

  const BangumiApiException(this.message, {this.statusCode, this.cause});

  @override
  String toString() {
    final status = statusCode == null ? '' : ' ($statusCode)';
    final detail = cause == null ? '' : ': $cause';
    return 'BangumiApiException$status: $message$detail';
  }
}

class BangumiApiService {
  // 目前bangumi被墙了，使用公开反向代理，来源文章:
  // https://catcat.blog/2026/05/bangumi-reverse-proxy
  // API: https://bgmapi.anibt.net  图片API: https://bgmimg.anibt.net
  // 感谢作者大大，好人一生平安
  static const _defaultBaseUrl = 'https://bgmapi.anibt.net/v0/';
  static final _primaryCalendarUri = Uri.parse(
    'https://bgmapi.anibt.net/calendar',
  );

  final http.Client _client;
  final Uri _baseUri;
  final Duration _timeout;
  final bool _ownsClient;

  BangumiApiService({
    http.Client? client,
    Uri? baseUri,
    Duration timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client(),
       _baseUri = baseUri ?? Uri.parse(_defaultBaseUrl),
       _timeout = timeout,
       _ownsClient = client == null;

  Future<BangumiSearchPage> searchSubjects(
    String keyword, {
    int limit = 20,
    int offset = 0,
    String sort = 'heat',
    bool includeNsfw = false,
    List<String> tags = const [],
    List<String> airDate = const [],
  }) async {
    _validatePage(limit, offset);
    final response = await _requestJson(
      '搜索番剧',
      () => _client.post(
        _endpoint('search/subjects', {'limit': '$limit', 'offset': '$offset'}),
        headers: _headers(json: true),
        body: jsonEncode({
          'keyword': keyword.trim(),
          'sort': sort,
          'filter': {
            'type': [2],
            'nsfw': includeNsfw,
            if (tags.isNotEmpty) 'tag': tags,
            if (airDate.isNotEmpty) 'air_date': airDate,
          },
        }),
      ),
    );

    final data = _asMap(response);
    final subjects = _asList(data['data'])
        .map(BangumiSubject.fromJson)
        .where((subject) => subject.id > 0)
        .toList(growable: false);
    return BangumiSearchPage(subjects: subjects, total: _asInt(data['total']));
  }

  Future<List<BangumiSubject>> getPopularSubjects({
    int limit = 20,
    int offset = 0,
  }) async {
    final result = await searchSubjects(
      '',
      limit: limit,
      offset: offset,
      sort: 'heat',
    );
    return result.subjects;
  }

  Future<List<BangumiSubject>> getCurrentSeasonPopularSubjects({
    int limit = 20,
    int offset = 0,
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now();
    final seasonStartMonth = ((current.month - 1) ~/ 3) * 3 + 1;
    final seasonStart = DateTime(current.year, seasonStartMonth, 1);
    final nextSeasonStart = DateTime(current.year, seasonStartMonth + 3, 1);

    final result = await searchSubjects(
      '',
      limit: limit,
      offset: offset,
      sort: 'heat',
      tags: const ['日本'],
      airDate: [
        '>=${_formatDate(seasonStart)}',
        '<${_formatDate(nextSeasonStart)}',
      ],
    );
    return result.subjects;
  }

  Future<List<BangumiCalendarDay>> getCalendar() async {
    final response = await _requestJson(
      '获取反向代理放送日历',
      () => _client.get(_primaryCalendarUri, headers: _headers()),
    );
    final days = _parseCalendar(response);
    if (days.isEmpty) {
      throw const BangumiApiException('放送日历没有有效数据');
    }
    return days;
  }

  Future<BangumiSubject> getSubject(int subjectId) async {
    _validateId(subjectId);
    final response = await _requestJson(
      '获取番剧详情',
      () => _client.get(_endpoint('subjects/$subjectId'), headers: _headers()),
    );
    final data = _asMap(response);
    final subject = BangumiSubject.fromJson(data);
    if (subject.id <= 0) {
      throw const BangumiApiException('番剧详情缺少有效 ID');
    }
    return subject;
  }

  Future<List<BangumiEpisode>> getEpisodes(
    int subjectId, {
    int limit = 100,
    int offset = 0,
  }) async {
    _validateId(subjectId);
    _validatePage(limit, offset);
    final response = await _requestJson(
      '获取番剧分集',
      () => _client.get(
        _endpoint('episodes', {
          'subject_id': '$subjectId',
          'limit': '$limit',
          'offset': '$offset',
        }),
        headers: _headers(),
      ),
    );
    return _asList(_asMap(response)['data'])
        .map(BangumiEpisode.fromJson)
        .where((episode) => episode.id > 0)
        .toList(growable: false);
  }

  Future<dynamic> _requestJson(
    String operation,
    Future<http.Response> Function() request, {
    bool logFailure = true,
  }) async {
    try {
      final response = await request().timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw BangumiApiException(
          '$operation请求失败',
          statusCode: response.statusCode,
        );
      }
      try {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException catch (error) {
        throw BangumiApiException('$operation返回了无效 JSON', cause: error);
      }
    } on BangumiApiException catch (error, stackTrace) {
      if (logFailure) {
        AppLogger.error('bangumi', error.message, error, stackTrace);
      }
      rethrow;
    } on TimeoutException catch (error, stackTrace) {
      final exception = BangumiApiException('$operation超时', cause: error);
      if (logFailure) {
        AppLogger.error('bangumi', exception.message, exception, stackTrace);
      }
      throw exception;
    } catch (error, stackTrace) {
      final exception = BangumiApiException('$operation失败', cause: error);
      if (logFailure) {
        AppLogger.error('bangumi', exception.message, error, stackTrace);
      }
      throw exception;
    }
  }

  List<BangumiCalendarDay> _parseCalendar(Object? response) {
    if (response is List) {
      final days = response
          .whereType<Map>()
          .map(
            (item) =>
                BangumiCalendarDay.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((day) => day.weekdayId > 0)
          .toList(growable: false);
      return _sortCalendar(days);
    }

    if (response is Map) {
      final map = Map<String, dynamic>.from(response);
      final days = <BangumiCalendarDay>[];
      for (var weekday = 1; weekday <= 7; weekday++) {
        final entries = map['$weekday'];
        if (entries is! List) continue;
        final subjects = <BangumiSubject>[];
        for (final entry in entries) {
          if (entry is! Map) continue;
          final item = Map<String, dynamic>.from(entry);
          final subject = item['subject'];
          final subjectJson = subject is Map ? subject : item;
          final parsed = BangumiSubject.fromJson(
            Map<String, dynamic>.from(subjectJson),
          );
          if (parsed.id > 0) subjects.add(parsed);
        }
        days.add(
          BangumiCalendarDay(
            weekdayId: weekday,
            weekdayCn: '星期${_weekdayNames[weekday - 1]}',
            weekdayEn: _weekdayEnglishNames[weekday - 1],
            subjects: subjects,
          ),
        );
      }
      return days;
    }

    return const [];
  }

  List<BangumiCalendarDay> _sortCalendar(List<BangumiCalendarDay> days) {
    return days.toList(growable: true)
      ..sort((left, right) => left.weekdayId.compareTo(right.weekdayId));
  }

  Map<String, String> _headers({bool json = false}) => {
    'Accept': 'application/json',
    'User-Agent': 'ZZZFun/1.0',
    if (json) 'Content-Type': 'application/json',
  };

  Uri _endpoint(String path, [Map<String, String> query = const {}]) {
    final uri = _baseUri.resolve(path);
    return query.isEmpty ? uri : uri.replace(queryParameters: query);
  }

  void _validatePage(int limit, int offset) {
    if (limit < 1 || limit > 100) {
      throw const BangumiApiException('limit 必须在 1 到 100 之间');
    }
    if (offset < 0) {
      throw const BangumiApiException('offset 不能小于 0');
    }
  }

  void _validateId(int subjectId) {
    if (subjectId <= 0) {
      throw const BangumiApiException('番剧 ID 必须大于 0');
    }
  }

  Future<void> close() async {
    if (_ownsClient) _client.close();
  }
}

const _weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];
const _weekdayEnglishNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _formatDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
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

int _asInt(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
