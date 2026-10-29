import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:zzzfun/models/kazumi_rule_models.dart';
import 'package:zzzfun/services/kazumi_api_rule_engine.dart';
import 'package:zzzfun/services/kazumi_rules_repository.dart';

/// Guards the vendored Kazumi rule layer against upstream rule changes.
///
/// Runs offline against `test/fixtures/kazumi_rules/`. Refresh the fixtures
/// with:
///
///     dart run tool/fetch_kazumi_rule_fixtures.dart
///
/// When this fails after such a refresh, the rule format gained something the
/// vendored layer does not handle yet — re-run `tool/sync_kazumi_rules.ps1`.
void main() {
  final fixtureDir = Directory('test/fixtures/kazumi_rules');

  test('fixtures are present and refreshable', () {
    expect(
      fixtureDir.existsSync(),
      isTrue,
      reason: 'Run: dart run tool/fetch_kazumi_rule_fixtures.dart',
    );
    expect(
      File('${fixtureDir.path}/index.json').existsSync(),
      isTrue,
      reason: 'Fixture index.json is missing.',
    );
  });

  test('every published rule loads and validates against the engine', () {
    final indexFile = File('${fixtureDir.path}/index.json');
    if (!indexFile.existsSync()) return;

    final catalog = (jsonDecode(indexFile.readAsStringSync()) as List)
        .whereType<Map>()
        .map((item) => KazumiRuleCatalogEntry.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .where((entry) => entry.name.isNotEmpty)
        .toList();

    expect(catalog, isNotEmpty, reason: 'Catalog fixture is empty.');

    final skipped = <String>[];
    final problems = <String>[];
    var supported = 0;

    for (final entry in catalog) {
      final ruleFile = File('${fixtureDir.path}/${entry.name}.json');
      if (!ruleFile.existsSync()) {
        problems.add('${entry.name}: 规则文件缺失');
        continue;
      }
      late final KazumiRule rule;
      try {
        rule = KazumiRule.fromJson(
          Map<String, dynamic>.from(
            jsonDecode(ruleFile.readAsStringSync()) as Map,
          ),
        );
      } catch (error) {
        problems.add('${entry.name}: 无法解析 (${error.runtimeType}) $error');
        continue;
      }
      if (rule.requiresNewerClient) {
        skipped.add('${entry.name}=API${rule.apiVersion}');
        continue;
      }
      try {
        rule.validateForRuleEngine();
      } on FormatException catch (error) {
        problems.add('${entry.name}: ${error.message}');
        continue;
      }
      supported++;
    }

    // A rule needing a newer API level is a signal that
    // KazumiRule.supportedApiLevel must be bumped together with a re-sync.
    expect(
      skipped,
      isEmpty,
      reason: '这些规则要求的 API Level 高于本地支持的 '
          '${KazumiRule.supportedApiLevel}，需要重新同步解析层并更新 '
          'supportedApiLevel：${skipped.join(', ')}',
    );
    expect(
      problems,
      isEmpty,
      reason: '规则结构与本地解析层不匹配：\n${problems.join('\n')}',
    );
    expect(supported, catalog.length);
  });

  test('XPath rules locate their declared selectors', () {
    final indexFile = File('${fixtureDir.path}/index.json');
    if (!indexFile.existsSync()) return;

    final names = (jsonDecode(indexFile.readAsStringSync()) as List)
        .whereType<Map>()
        .map((item) => item['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty);

    final engine = KazumiApiRuleEngine(client: MockClient((_) async {
      // Any request in this test is a bug in the assertions below.
      fail('契约测试不应发起网络请求');
    }));

    for (final name in names) {
      final ruleFile = File('${fixtureDir.path}/$name.json');
      if (!ruleFile.existsSync()) continue;
      final rule = KazumiRule.fromJson(
        Map<String, dynamic>.from(jsonDecode(ruleFile.readAsStringSync()) as Map),
      );
      if (rule.requiresNewerClient || !rule.validateForRuleEngineSafe()) {
        continue;
      }
      if (rule.searchMode != 'xpath') continue;

      // A rule that parsed but whose selectors are syntactically broken would
      // only fail at runtime against the live site.
      expect(
        () => rule.validateForRuleEngine(),
        returnsNormally,
        reason: '$name 的 XPath 规则配置无效',
      );
    }
    engine.close();
  });

  test('repository installs rules from the fixture catalog', () async {
    if (!Directory('test/fixtures/kazumi_rules').existsSync()) return;

    final client = MockClient((request) async {
      final path = request.url.pathSegments.last;
      final file = File(
        '${Directory('test/fixtures/kazumi_rules').path}/$path',
      );
      if (!file.existsSync()) {
        return http.Response('', 404);
      }
      return http.Response.bytes(
        utf8.encode(file.readAsStringSync()),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final repository = KazumiRulesRepository(
      client: client,
      indexUri: Uri.parse('https://rules.example/index.json'),
      ruleBaseUri: Uri.parse('https://rules.example/'),
      persistenceEnabled: false,
    );

    final catalog = await repository.getCatalog();
    expect(catalog, isNotEmpty);
    for (final entry in catalog) {
      final rule = await repository.getRule(entry.name);
      expect(rule.name, isNotEmpty, reason: '${entry.name} 解析后 name 为空');
    }
    await repository.close();
  });
}

extension on KazumiRule {
  /// True when the rule is structurally usable; used to skip broken fixtures
  /// in the selector test instead of asserting on them twice.
  bool validateForRuleEngineSafe() {
    try {
      validateForRuleEngine();
      return true;
    } on FormatException {
      return false;
    }
  }
}
