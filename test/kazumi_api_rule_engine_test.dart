import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:zzzfun/models/kazumi_rule_models.dart';
import 'package:zzzfun/models/video_source_models.dart';
import 'package:zzzfun/services/kazumi_api_rule_engine.dart';
import 'package:zzzfun/services/video_resource_service.dart';

void main() {
  test('adds browser-like headers to XPath rule requests', () async {
    final rule = KazumiRule.fromJson({
      'api': '5',
      'type': 'anime',
      'name': 'dm84-test',
      'version': '1.0',
      'baseURL': 'https://example.com/',
      'searchURL': 'https://example.com/s----------.html?wd=@keyword',
      'searchList': '//div',
      'searchName': '//a',
      'searchResult': '//a',
      'chapterRoads': '//div',
      'chapterResult': '//a',
    });
    final client = MockClient((request) async {
      expect(request.headers['Accept-Language'], 'zh-CN,zh;q=0.9');
      expect(request.headers['Connection'], 'keep-alive');
      expect(request.headers['User-Agent'], startsWith('Mozilla/5.0'));
      return http.Response(
        '<div><a href="/subject/1">幼女战记 第二季</a></div>',
        200,
        headers: {'content-type': 'text/html'},
      );
    });
    final engine = KazumiApiRuleEngine(client: client);

    final results = await engine.search(rule, '幼女战记 第二季');

    expect(results.single.source, 'https://example.com/subject/1');
    await engine.close();
  });

  test('executes an API rule search with query placeholders', () async {
    final rule = KazumiRule.fromJson(
      _apiRuleJson(
        userAgent: 'ZZZFun-Test/1.0',
        searchApiConfig: {
          'request': {
            'method': 'GET',
            'url': 'https://example.com/api/search',
            'query': {'q': '@keyword', 'page': 1},
          },
          'listPath': r'$.data[*]',
          'namePath': r'$.title',
          'sourcePath': r'$.id',
        },
      ),
    );
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.queryParameters['q'], '银河铁道');
      expect(request.url.queryParameters['page'], '1');
      expect(request.headers['User-Agent'], 'ZZZFun-Test/1.0');
      expect(request.headers['Accept-Language'], 'zh-CN,zh;q=0.9');
      expect(request.headers['Connection'], 'keep-alive');
      return http.Response(
        jsonEncode({
          'data': [
            {'id': 12, 'title': '银河铁道之夜'},
            {'id': '13', 'title': '银河铁道续篇'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final engine = KazumiApiRuleEngine(client: client);

    final results = await engine.search(rule, '银河铁道');

    expect(results, hasLength(2));
    expect(results.first.name, '银河铁道之夜');
    expect(results.first.source, '12');
    await engine.close();
  });

  test('executes a JSON POST rule and keeps numeric placeholders', () async {
    final rule = KazumiRule.fromJson(
      _apiRuleJson(
        userAgent: 'TestAgent/2.0',
        searchApiConfig: {
          'request': {
            'method': 'POST',
            'url': 'https://example.com/api/search',
            'headers': {'X-Test': 'enabled'},
            'bodyType': 'json',
            'body': {'keyword': '@keyword', 'page': 1},
          },
          'listPath': r'$[*]',
          'namePath': r'$.name',
          'sourcePath': r'$.source',
        },
      ),
    );
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.headers['X-Test'], 'enabled');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['keyword'], '测试');
      expect(body['page'], 1);
      return http.Response(
        jsonEncode([
          {'source': 'abc', 'name': '测试番剧'},
        ]),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final engine = KazumiApiRuleEngine(client: client);

    final results = await engine.search(rule, '测试');

    expect(results.single.name, '测试番剧');
    await engine.close();
  });

  test('parses nested roads, variables, episode pages and indexes', () async {
    final rule = KazumiRule.fromJson(
      _apiRuleJson(
        referer: 'https://example.com/',
        chapterApiConfig: {
          'request': {
            'method': 'GET',
            'url': 'https://example.com/api/detail/@source',
          },
          'format': 'nested',
          'roadsPath': r'$.data.playSources[*]',
          'roadNamePath': r'$.name',
          'episodesPath': r'$.episodes[*]',
          'episodeNamePath': r'$.title',
          'episodeUrlPath': r'$.id',
          'variables': {'slug': r'$.data.slug'},
          'episodePage': {
            'url': 'https://example.com/play/@slug',
            'query': {'source': '@roadIndex', 'episode': '@episodeIndex'},
          },
        },
      ),
    );
    final client = MockClient((request) async {
      expect(request.url.path, '/api/detail/subject-42');
      expect(request.headers['Referer'], 'https://example.com/');
      return http.Response(
        jsonEncode({
          'data': {
            'slug': 'demo-anime',
            'playSources': [
              {
                'name': '线路 A',
                'episodes': [
                  {'id': 'ep-a1', 'title': '第 1 集'},
                  {'id': 'ep-a2', 'title': '第 2 集'},
                ],
              },
              {
                'name': '线路 B',
                'episodes': [
                  {'id': 'ep-b1', 'title': '第 1 集'},
                ],
              },
            ],
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final engine = KazumiApiRuleEngine(client: client);
    const item = VideoSearchItem(
      name: '示例番剧',
      source: 'subject-42',
      ruleName: 'demo',
    );

    final result = await engine.getChapters(rule, item);

    expect(result.sources, hasLength(2));
    expect(result.sources.first.episodes, hasLength(2));
    expect(
      result.sources.first.episodes.first.pageUrl,
      'https://example.com/play/demo-anime?source=0&episode=0',
    );
    expect(
      result.sources[1].episodes.single.pageUrl,
      'https://example.com/play/demo-anime?source=1&episode=0',
    );
    expect(
      result.sources.first.episodes.first.requestHeaders['Referer'],
      'https://example.com/',
    );
    await engine.close();
  });

  test(
    'searchWithAliases retries the next alias after an empty result',
    () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        if (request.url.path.endsWith('/index.json')) {
          return http.Response(
            jsonEncode([
              {
                'name': 'demo',
                'version': '1.0',
                'useNativePlayer': true,
                'antiCrawlerEnabled': false,
              },
            ]),
            200,
          );
        }
        if (request.url.path.endsWith('/demo.json')) {
          return http.Response(
            jsonEncode(
              _apiRuleJson(
                searchApiConfig: {
                  'request': {
                    'method': 'GET',
                    'url': 'https://example.com/api/search',
                    'query': {'q': '@keyword'},
                  },
                  'listPath': r'$.data[*]',
                  'namePath': r'$.name',
                  'sourcePath': r'$.id',
                },
              ),
            ),
            200,
          );
        }
        final keyword = request.url.queryParameters['q'];
        return http.Response(
          jsonEncode(
            keyword == '主标题'
                ? {'data': []}
                : {
                    'data': [
                      {'id': 'alias-1', 'name': '别名结果'},
                    ],
                  },
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final service = VideoResourceService(
        client: client,
        indexUri: Uri.parse('https://rules.example/index.json'),
        ruleBaseUri: Uri.parse('https://rules.example/'),
      );

      final results = await service.searchWithAliases('demo', ['主标题', '别名']);

      expect(results.single.name, '别名结果');
      expect(requests, 3);
      await service.close();
    },
  );

  test(
    'executes a legacy XPath rule with relative search and episode links',
    () async {
      final rule = KazumiRule.fromJson({
        'api': '4',
        'type': 'anime',
        'name': 'legacy-demo',
        'version': '1.0',
        'muliSources': true,
        'useWebview': true,
        'useNativePlayer': true,
        'useLegacyParser': true,
        'baseURL': 'https://example.com/',
        'searchURL': 'https://example.com/search?wd=@keyword',
        'searchList': "//div[@class='entry']",
        'searchName': '//span',
        'searchResult': '//a',
        'chapterRoads': "//div[@class='road']",
        'chapterResult': '//a',
      });
      final client = MockClient((request) async {
        if (request.url.path == '/search') {
          expect(request.method, 'GET');
          expect(request.url.queryParameters['wd'], '测试番剧');
          return http.Response.bytes(
            utf8.encode('''<html><body>
            <div class="entry"><a href="/detail/demo"><span>测试番剧</span></a></div>
          </body></html>'''),
            200,
          );
        }
        expect(request.url.path, '/detail/demo');
        return http.Response.bytes(
          utf8.encode('''<html><body>
          <div class="road">
            <a href="/play/demo-1">第 1 集</a>
            <a href="/play/demo-2">第 2 集</a>
          </div>
        </body></html>'''),
          200,
        );
      });
      final engine = KazumiApiRuleEngine(client: client);

      final results = await engine.search(rule, '测试番剧');
      expect(results.single.source, 'https://example.com/detail/demo');

      final chapters = await engine.getChapters(rule, results.single);
      expect(chapters.sources, hasLength(1));
      expect(chapters.sources.single.episodes, hasLength(2));
      expect(
        chapters.sources.single.episodes.first.pageUrl,
        'https://example.com/play/demo-1',
      );
      expect(chapters.sources.single.episodes.first.useLegacyParser, isTrue);
      await engine.close();
    },
  );

  test('parses API delimited chapter responses', () async {
    final rule = KazumiRule.fromJson(
      _apiRuleJson(
        chapterApiConfig: {
          'request': {
            'method': 'GET',
            'url': 'https://example.com/api/detail/@source',
          },
          'format': 'delimited',
          'roadNamesPath': r'$.data.roadNames',
          'roadEpisodesPath': r'$.data.episodes',
          'roadSeparator': '|||',
          'episodeSeparator': '#',
          'fieldSeparator': r'$;',
          'episodePage': {'url': '@episodeUrl', 'query': {}},
        },
      ),
    );
    final client = MockClient((request) async {
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'data': {
              'roadNames': '主线路|||备用线路',
              'episodes':
                  r'第一集$;https://example.com/a#第二集$;https://example.com/b'
                  r'|||第一集$;https://example.com/c',
            },
          }),
        ),
        200,
      );
    });
    final engine = KazumiApiRuleEngine(client: client);
    const item = VideoSearchItem(
      name: '示例番剧',
      source: 'subject-42',
      ruleName: 'demo',
    );

    final result = await engine.getChapters(rule, item);

    expect(result.sources, hasLength(2));
    expect(result.sources.first.name, '主线路');
    expect(result.sources.first.episodes, hasLength(2));
    expect(result.sources[1].name, '备用线路');
    await engine.close();
  });

  test(
    'reports an enabled XPath anti-crawler page for WebView verification',
    () async {
      final rule = KazumiRule.fromJson({
        'api': '6',
        'type': 'anime',
        'name': 'captcha-demo',
        'version': '1.0',
        'baseURL': 'https://example.com/',
        'searchURL': 'https://example.com/search?wd=@keyword',
        'searchList': '//div[@class="entry"]',
        'searchName': '//span',
        'searchResult': '//a',
        'chapterRoads': '//div',
        'chapterResult': '//a',
        'antiCrawlerConfig': {
          'enabled': true,
          'captchaType': 1,
          'captchaImage': '//img[@class="captcha"]',
          'captchaInput': '//input',
          'captchaButton': '//button',
        },
      });
      final engine = KazumiApiRuleEngine(
        client: MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(
              '<html><body><img class="captcha" src="captcha.png"></body></html>',
            ),
            200,
          ),
        ),
      );

      await expectLater(
        engine.search(rule, '测试'),
        throwsA(isA<KazumiCaptchaRequiredException>()),
      );
      await engine.close();
    },
  );
}

Map<String, dynamic> _apiRuleJson({
  String userAgent = '',
  String referer = '',
  Map<String, dynamic>? searchApiConfig,
  Map<String, dynamic>? chapterApiConfig,
}) => {
  'api': '8',
  'type': 'anime',
  'name': 'demo',
  'version': '1.0',
  'muliSources': true,
  'useWebview': true,
  'useNativePlayer': true,
  'usePost': false,
  'userAgent': userAgent,
  'baseURL': 'https://example.com/',
  'referer': referer,
  'searchMode': 'api',
  'chapterMode': 'api',
  'searchApiConfig':
      searchApiConfig ??
      {
        'request': {'method': 'GET', 'url': 'https://example.com/api/search'},
        'listPath': r'$.data[*]',
        'namePath': r'$.name',
        'sourcePath': r'$.id',
      },
  'chapterApiConfig':
      chapterApiConfig ??
      {
        'request': {
          'method': 'GET',
          'url': 'https://example.com/api/detail/@source',
        },
        'format': 'nested',
        'roadsPath': r'$.data',
        'episodesPath': r'$.episodes[*]',
        'episodeNamePath': r'$.name',
        'episodeUrlPath': r'$.url',
        'episodePage': {'url': '@episodeUrl', 'query': {}},
      },
};
