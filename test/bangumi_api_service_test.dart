import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:zzzfun/services/bangumi_api_service.dart';

void main() {
  test('parses Bangumi subject metadata with aliases and images', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/v0/subjects/42');
      return http.Response(
        jsonEncode({
          'id': 42,
          'type': 2,
          'platform': 'TV',
          'name': 'Example',
          'name_cn': '示例番剧',
          'summary': '简介',
          'date': '2026-01-01',
          'eps': 12,
          'images': {'large': 'https://example.com/poster.jpg'},
          'infobox': [
            {
              'key': '别名',
              'value': [
                {'v': 'Alias'},
                {'v': '别名'},
              ],
            },
          ],
          'rating': {'score': 8.6, 'rank': 12, 'total': 1000},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final service = BangumiApiService(client: client);

    final subject = await service.getSubject(42);

    expect(subject.displayName, '示例番剧');
    expect(subject.episodeCount, 12);
    expect(subject.largeImage, 'https://example.com/poster.jpg');
    expect(subject.aliases, ['Alias', '别名']);
    expect(subject.ratingScore, 8.6);
  });

  test('posts search parameters and parses results', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/v0/search/subjects');
      expect(request.url.queryParameters['limit'], '3');
      expect(request.url.queryParameters['offset'], '6');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['keyword'], '关键词');
      expect(body['sort'], 'heat');
      return http.Response(
        jsonEncode({
          'total': 1,
          'data': [
            {'id': 7, 'name': 'Example', 'name_cn': '示例'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final service = BangumiApiService(client: client);

    final page = await service.searchSubjects('关键词', limit: 3, offset: 6);

    expect(page.total, 1);
    expect(page.subjects.single.id, 7);
  });

  test('filters popular subjects to the current season', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/v0/search/subjects');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final filter = body['filter'] as Map<String, dynamic>;
      expect(body['sort'], 'heat');
      expect(filter['type'], [2]);
      expect(filter['tag'], ['日本']);
      expect(filter['air_date'], ['>=2026-07-01', '<2026-10-01']);
      return http.Response(
        jsonEncode({
          'total': 1,
          'data': [
            {'id': 8, 'name': 'Summer Example', 'name_cn': '夏季番剧'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final service = BangumiApiService(client: client);

    final subjects = await service.getCurrentSeasonPopularSubjects(
      limit: 24,
      now: DateTime(2026, 8, 20),
    );

    expect(subjects.single.displayName, '夏季番剧');
  });

  test('maps non-success responses to BangumiApiException', () async {
    final service = BangumiApiService(
      client: MockClient((_) async => http.Response('not found', 404)),
    );

    await expectLater(
      service.getSubject(42),
      throwsA(
        isA<BangumiApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          404,
        ),
      ),
    );
  });

  test('parses episode list', () async {
    final service = BangumiApiService(
      client: MockClient((request) async {
        expect(request.url.path, '/v0/episodes');
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 99,
                'sort': 1,
                'type': 0,
                'name': 'Episode 1',
                'name_cn': '第 1 集',
                'airdate': '2026-01-02',
                'duration': '24:00',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final episodes = await service.getEpisodes(42);

    expect(episodes.single.displayName, '第 1 集');
    expect(episodes.single.sort, 1);
  });

  test('parses weekly calendar days and subjects', () async {
    final service = BangumiApiService(
      client: MockClient((request) async {
        expect(request.url.path, '/calendar');
        return http.Response(
          jsonEncode({
            '1': [
              {
                'subject': {
                  'id': 42,
                  'name': 'Example',
                  'nameCN': '示例番剧',
                  'info': '12话 / 2026年8月17日',
                  'metaTags': ['TV', '奇幻'],
                  'images': {'large': 'https://example.com/poster.jpg'},
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final days = await service.getCalendar();

    expect(days.single.weekdayCn, '星期一');
    expect(days.single.subjects.single.displayName, '示例番剧');
    expect(days.single.subjects.single.airDate, '2026-08-17');
  });
}
