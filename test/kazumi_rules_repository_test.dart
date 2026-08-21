import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zzzfun/services/kazumi_rules_repository.dart';

void main() {
  test('loads and caches the KazumiRules catalog and rule files', () async {
    var catalogRequests = 0;
    var ruleRequests = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/index.json')) {
        catalogRequests++;
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
        ruleRequests++;
        return http.Response(
          jsonEncode({
            'api': '8',
            'type': 'anime',
            'name': 'demo',
            'version': '1.0',
            'searchMode': 'api',
            'chapterMode': 'api',
            'searchApiConfig': {'request': {}},
            'chapterApiConfig': {'request': {}},
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    });
    final repository = KazumiRulesRepository(
      client: client,
      indexUri: Uri.parse('https://rules.example/index.json'),
      ruleBaseUri: Uri.parse('https://rules.example/'),
    );

    final firstCatalog = await repository.getCatalog();
    final secondCatalog = await repository.getCatalog();
    final firstRule = await repository.getRule('demo');
    final secondRule = await repository.getRule('demo');

    expect(firstCatalog.single.name, 'demo');
    expect(secondCatalog.single.name, 'demo');
    expect(firstRule.name, 'demo');
    expect(identical(firstRule, secondRule), isTrue);
    expect(catalogRequests, 1);
    expect(ruleRequests, 1);
    await repository.close();
  });

  test('rejects unsafe rule names before making a request', () async {
    final repository = KazumiRulesRepository(
      client: MockClient((_) async => http.Response('', 200)),
    );

    await expectLater(
      repository.getRule('../secret'),
      throwsA(isA<KazumiRulesException>()),
    );
    await repository.close();
  });

  test('persists installed rules and reads them without the network', () async {
    SharedPreferences.setMockInitialValues({});
    var ruleRequests = 0;
    final client = MockClient((request) async {
      ruleRequests++;
      return http.Response(
        jsonEncode({
          'api': '8',
          'type': 'anime',
          'name': 'demo',
          'version': '2.0',
          'searchMode': 'api',
          'chapterMode': 'api',
          'searchApiConfig': {'request': {}},
          'chapterApiConfig': {'request': {}},
        }),
        200,
      );
    });
    final repository = KazumiRulesRepository(
      client: client,
      ruleBaseUri: Uri.parse('https://rules.example/'),
    );

    final installed = await repository.installRule('demo');
    expect(installed.version, '2.0');
    expect((await repository.getInstalledRules()).single.name, 'demo');
    await repository.close();

    final offlineRepository = KazumiRulesRepository(
      client: MockClient((_) async => http.Response('', 503)),
      ruleBaseUri: Uri.parse('https://rules.example/'),
    );
    final cached = await offlineRepository.getRule('demo');
    expect(cached.version, '2.0');
    expect(ruleRequests, 1);
    await offlineRepository.uninstallRule('demo');
    expect(await offlineRepository.getInstalledRules(), isEmpty);
    await offlineRepository.close();
  });

  test('refreshCatalog bypasses the cached catalog', () async {
    SharedPreferences.setMockInitialValues({});
    var version = '1.0';
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode([
          {
            'name': 'demo',
            'version': version,
            'useNativePlayer': true,
            'antiCrawlerEnabled': false,
          },
        ]),
        200,
      );
    });
    final repository = KazumiRulesRepository(
      client: client,
      indexUri: Uri.parse('https://rules.example/index.json'),
      ruleBaseUri: Uri.parse('https://rules.example/'),
    );

    expect((await repository.getCatalog()).single.version, '1.0');
    version = '2.0';
    expect((await repository.getCatalog()).single.version, '1.0');
    expect((await repository.refreshCatalog()).single.version, '2.0');
    await repository.close();
  });
}
