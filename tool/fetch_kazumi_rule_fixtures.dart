// Downloads the published KazumiRules catalog into test fixtures.
//
//   dart run tool/fetch_kazumi_rule_fixtures.dart
//
// The fixtures are checked in so `flutter test` stays offline. Run this
// whenever you sync the vendored parser, then look at the contract test:
// a failing one means the rule format moved ahead of the parser.
import 'dart:convert';
import 'dart:io';

const _indexUrl =
    'https://raw.githubusercontent.com/Predidit/KazumiRules/main/index.json';
const _ruleBase = 'https://raw.githubusercontent.com/Predidit/KazumiRules/main/';
const _mirrorBase =
    'https://cdn.jsdelivr.net/gh/Predidit/KazumiRules@main/';

Future<void> main(List<String> args) async {
  final outputDir = Directory(
    args.isNotEmpty ? args.first : 'test/fixtures/kazumi_rules',
  );
  if (!outputDir.existsSync()) {
    outputDir.createSync(recursive: true);
  }

  final client = HttpClient();
  try {
    final index = await _get(client, _indexUrl);
    final catalog = jsonDecode(index);
    if (catalog is! List) {
      throw StateError('index.json is not a JSON array');
    }
    File('${outputDir.path}/index.json').writeAsStringSync(index);
    stdout.writeln('index.json: ${catalog.length} rules');

    var written = 0;
    final skipped = <String>[];
    for (final item in catalog.whereType<Map>()) {
      final name = item['name']?.toString().trim() ?? '';
      if (name.isEmpty || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(name)) {
        skipped.add('${item['name']} (invalid name)');
        continue;
      }
      try {
        final body = await _get(client, '$_ruleBase$name.json');
        File('${outputDir.path}/$name.json').writeAsStringSync(body);
        written++;
        stdout.writeln('  $name ${item['version']}');
      } catch (error) {
        skipped.add('$name ($error)');
      }
    }
    if (skipped.isNotEmpty) {
      stdout.writeln('skipped: ${skipped.join(', ')}');
    }
    stdout.writeln('wrote $written rule files to ${outputDir.path}');
  } finally {
    client.close();
  }
}

Future<String> _get(HttpClient client, String url) async {
  final sources = [url, if (url.contains('raw.githubusercontent.com')) _mirrorBase + url.split('/main/').last];
  Object? lastError;
  for (final source in sources) {
    try {
      final request = await client.getUrl(Uri.parse(source));
      request.headers.set('User-Agent', 'ZZZFun-fixtures');
      final response = await request.close();
      if (response.statusCode != 200) {
        lastError = 'HTTP ${response.statusCode} for $source';
        continue;
      }
      return await response.transform(utf8.decoder).join();
    } catch (error) {
      lastError = error;
    }
  }
  throw StateError('$lastError');
}
