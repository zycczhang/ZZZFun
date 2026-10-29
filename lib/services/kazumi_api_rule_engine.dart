import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:kazumi_rules/plugins/api_rule_config.dart';
import 'package:kazumi_rules/services/plugin/api_rule_strategy.dart';
import 'package:kazumi_rules/services/plugin/rule_engine_models.dart';
import 'package:kazumi_rules/services/plugin/xpath_rule_strategy.dart';

import '../models/kazumi_rule_models.dart';
import '../models/video_source_models.dart';
import 'app_logger.dart';
import 'kazumi_rules_repository.dart';

/// Raised when a rule site answers with an anti-crawler challenge page.
///
/// Upstream's `CaptchaRequiredException` only carries the plugin name; this
/// variant also carries the URL the WebView verification dialog must load.
class KazumiCaptchaRequiredException implements Exception {
  final String ruleName;
  final String url;

  const KazumiCaptchaRequiredException(this.ruleName, this.url);

  @override
  String toString() => 'KazumiCaptchaRequiredException: $ruleName';
}

/// Executes Kazumi rules through the vendored upstream parsing layer.
///
/// Request preparation, templating, JSONPath and XPath parsing all come from
/// `packages/kazumi_rules`. What lives here is only the transport (upstream
/// uses Dio, this app uses `package:http`) and the small amount of
/// orchestration that upstream keeps in `RuleEngine`, which is not vendored
/// because it is hard-wired to Dio, Dio cookies and the app logger.
class KazumiApiRuleEngine {
  static const _defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/141.0.0.0 Safari/537.36';
  static const _defaultAcceptLanguage = 'zh-CN,zh;q=0.9';
  static const _apiStrategy = ApiRuleStrategy();
  static const _xpathStrategy = XPathRuleStrategy();

  final http.Client _client;
  final Duration _timeout;
  final bool _ownsClient;
  final Map<String, String> _cookieHeaders = {};

  KazumiApiRuleEngine({
    http.Client? client,
    Duration timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client(),
       _timeout = timeout,
       _ownsClient = client == null;

  void setCookieHeader(String ruleName, String cookieHeader) {
    final normalized = cookieHeader.trim();
    if (normalized.isEmpty) {
      _cookieHeaders.remove(ruleName);
    } else {
      _cookieHeaders[ruleName] = normalized;
    }
  }

  Future<List<VideoSearchItem>> search(KazumiRule rule, String keyword) async {
    rule.validateForRuleEngine();
    final config = _configFor(rule);
    try {
      final request = config.searchMode == RuleMode.api
          ? _apiStrategy.prepareRequest(config.searchApiConfig.request, {
              'keyword': keyword.trim(),
            })
          : _xpathStrategy.prepareSearchRequest(config, keyword.trim());
      final raw = await _execute(request, config, userAgent: rule.userAgent);
      final parsed = config.searchMode == RuleMode.api
          ? _apiStrategy.parseSearch(raw, config.searchApiConfig)
          : _xpathStrategy.parseSearch(raw, config);
      _logDiagnostics(rule, '搜索', parsed.diagnostics);
      return parsed.items
          .map(
            (item) => VideoSearchItem(
              name: item.name,
              // Upstream already renders `searchApiConfig.sourceTemplate` for
              // API rules, so `src` is a ready URL there. XPath rules return a
              // raw href, which the chapter request normalizes on its own; make
              // it absolute here only so the UI can display an address.
              source: config.searchMode == RuleMode.api
                  ? item.src
                  : _absoluteSource(rule, item.src),
              ruleName: rule.name,
            ),
          )
          .toList(growable: false);
    } on CaptchaRequiredException {
      throw KazumiCaptchaRequiredException(
        rule.name,
        _captchaUrl(rule, keyword),
      );
    } on FormatException {
      rethrow;
    } on ApiRuleFormatException catch (error) {
      throw FormatException(error.message);
    } on XPathRuleFormatException catch (error) {
      throw FormatException(error.message);
    } catch (error) {
      throw _failure('搜索 ${rule.name}', error);
    }
  }

  Future<VideoChapterResult> getChapters(
    KazumiRule rule,
    VideoSearchItem item,
  ) async {
    rule.validateForRuleEngine();
    if (item.ruleName != rule.name) {
      throw KazumiRulesException('搜索结果与规则不匹配');
    }
    final config = _configFor(rule);
    try {
      final request = config.chapterMode == RuleMode.api
          ? _apiStrategy.prepareRequest(config.chapterApiConfig.request, {
              'source': item.source,
            })
          : _xpathStrategy.prepareChapterRequest(config, item.source);
      final raw = await _execute(request, config, userAgent: rule.userAgent);
      final parsed = config.chapterMode == RuleMode.api
          ? _apiStrategy.parseChapters(
              raw,
              config.chapterApiConfig,
              source: item.source,
              baseUrl: config.baseUrl,
            )
          : _xpathStrategy.parseChapters(raw, config);
      _logDiagnostics(rule, '分集', parsed.diagnostics);
      final sources = <VideoSource>[];
      for (var roadIndex = 0; roadIndex < parsed.roads.length; roadIndex++) {
        final road = parsed.roads[roadIndex];
        final episodes = <VideoEpisode>[];
        for (var index = 0; index < road.data.length; index++) {
          episodes.add(
            VideoEpisode(
              name: index < road.identifier.length
                  ? road.identifier[index]
                  : '第${index + 1}集',
              pageUrl: road.data[index],
              roadIndex: roadIndex,
              episodeIndex: index,
              requestHeaders: _pageHeaders(rule),
              mediaHeaders: _mediaHeaders(rule),
              useLegacyParser: rule.useLegacyParser,
            ),
          );
        }
        if (episodes.isEmpty) continue;
        sources.add(VideoSource(name: road.name, episodes: episodes));
      }
      return VideoChapterResult(
        ruleName: rule.name,
        source: item.source,
        sources: sources,
      );
    } on FormatException {
      rethrow;
    } on ApiRuleFormatException catch (error) {
      throw FormatException(error.message);
    } on XPathRuleFormatException catch (error) {
      throw FormatException(error.message);
    } catch (error) {
      throw _failure('获取 ${rule.name} 分集', error);
    }
  }

  KazumiRulesException _failure(String operation, Object error) {
    if (error is KazumiRulesException) return error;
    AppLogger.warning('kazumi-rules', '$operation失败', error);
    return KazumiRulesException('$operation失败', cause: error);
  }

  void _logDiagnostics(KazumiRule rule, String phase, List<String> items) {
    if (items.isEmpty) return;
    final preview = items.take(3).join('; ');
    AppLogger.warning(
      'kazumi-rules',
      '${rule.name} $phase 跳过 ${items.length} 个节点: $preview',
    );
  }

  String _absoluteSource(KazumiRule rule, String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
      return value;
    }
    final base = rule.baseUrl;
    if (base == null || base.host.isEmpty) return value;
    return base.resolve(value).toString();
  }

  RuleExecutionConfig _configFor(KazumiRule rule) {
    return RuleExecutionConfig(
      pluginName: rule.name,
      baseUrl: rule.baseUrl?.toString() ?? '',
      usePost: rule.usePost,
      searchMode: rule.searchMode,
      chapterMode: rule.chapterMode,
      searchUrl: rule.searchUrl,
      searchList: rule.searchList,
      searchName: rule.searchName,
      searchResult: rule.searchResult,
      chapterRoads: rule.chapterRoads,
      chapterResult: rule.chapterResult,
      searchApiConfig: rule.searchApiConfig,
      chapterApiConfig: rule.chapterApiConfig,
      antiCrawlerConfig: rule.antiCrawlerConfig,
    );
  }

  /// URL the captcha dialog should load so the user can clear the challenge.
  String _captchaUrl(KazumiRule rule, String keyword) {
    final template = rule.searchUrl.trim();
    if (template.isEmpty) return rule.baseUrl?.toString() ?? '';
    return template.replaceAll('@keyword', Uri.encodeQueryComponent(keyword));
  }

  Map<String, String> _pageHeaders(KazumiRule rule) => {
    'User-Agent': rule.userAgent.isEmpty ? _defaultUserAgent : rule.userAgent,
    if (rule.referer.isNotEmpty) 'Referer': rule.referer,
  };

  Map<String, String> _mediaHeaders(KazumiRule rule) => {
    'User-Agent': rule.userAgent.isEmpty ? _defaultUserAgent : rule.userAgent,
    if (rule.referer.isNotEmpty) 'Referer': rule.referer,
  };

  Future<String> _execute(
    PreparedRuleRequest request,
    RuleExecutionConfig config, {
    required String userAgent,
  }) async {
    final uri = _buildUri(request.url, request.query);
    final headers = <String, String>{
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': _defaultAcceptLanguage,
      'Connection': 'keep-alive',
      'User-Agent': userAgent.isEmpty ? _defaultUserAgent : userAgent,
      // Upstream uses the site root as Referer for every rule request.
      if (config.baseUrl.trim().isNotEmpty)
        'Referer': '${config.baseUrl.trim().replaceAll(RegExp(r'/+$'), '')}/',
      if (request.includeCookies &&
          (_cookieHeaders[config.pluginName]?.isNotEmpty ?? false))
        'Cookie': _cookieHeaders[config.pluginName]!,
      for (final entry in request.headers.entries)
        _sanitizeHeaderName(entry.key): _sanitizeHeaderValue(entry.value),
    };
    final method = request.method.toUpperCase();
    final body = method == 'POST' && request.body != null
        ? _encodeBody(request, headers)
        : null;

    final http.Response response;
    try {
      response = await _send(method, uri, headers, body).timeout(_timeout);
    } on TimeoutException catch (error, stackTrace) {
      AppLogger.warning('kazumi-rules', '规则请求超时', error, stackTrace);
      throw KazumiRulesException('规则请求超时', cause: error);
    } catch (error, stackTrace) {
      if (error is KazumiRulesException) rethrow;
      AppLogger.warning('kazumi-rules', '规则请求失败', error, stackTrace);
      throw KazumiRulesException('规则请求失败', cause: error);
    }

    final decoded = _decodeBody(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      // Upstream inspects failed responses before giving up: protected sites
      // commonly answer the challenge page with 403/429/503.
      if (config.searchMode == RuleMode.xpath &&
          config.antiCrawlerConfig.enabled &&
          _xpathStrategy.detectsCaptchaChallenge(
            decoded,
            config.antiCrawlerConfig,
          )) {
        throw CaptchaRequiredException(config.pluginName);
      }
      throw KazumiRulesException(
        '规则请求失败',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  String _encodeBody(PreparedRuleRequest request, Map<String, String> headers) {
    if (request.bodyType == ApiBodyType.form) {
      headers.putIfAbsent(
        'Content-Type',
        () => 'application/x-www-form-urlencoded',
      );
      final body = request.body;
      if (body is Map) {
        return body.entries
            .map(
              (entry) =>
                  '${Uri.encodeQueryComponent(entry.key.toString())}='
                  '${Uri.encodeQueryComponent(entry.value?.toString() ?? '')}',
            )
            .join('&');
      }
      return body?.toString() ?? '';
    }
    headers.putIfAbsent('Content-Type', () => 'application/json');
    return jsonEncode(request.body);
  }

  Future<http.Response> _send(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) {
    switch (method) {
      case 'GET':
        return _client.get(uri, headers: headers);
      case 'POST':
        return _client.post(uri, headers: headers, body: body);
      default:
        throw KazumiRulesException('不支持的规则请求方法: $method');
    }
  }

  Uri _buildUri(String rawUrl, Map<String, dynamic> query) {
    final parsed = Uri.tryParse(rawUrl.trim());
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      throw KazumiRulesException('规则请求 URL 无效: $rawUrl');
    }
    if (parsed.scheme != 'http' && parsed.scheme != 'https') {
      throw KazumiRulesException('规则地址不是 HTTP(S) 地址: $rawUrl');
    }
    if (query.isEmpty) return parsed;
    return parsed.replace(
      queryParameters: {
        ...parsed.queryParameters,
        ...query.map((key, value) => MapEntry(key, value?.toString() ?? '')),
      },
    );
  }

  /// Decodes the body using the charset declared in `Content-Type`.
  ///
  /// Falls back to a lenient UTF-8 decode so a mis-declared body yields text
  /// instead of a FormatException on a stray byte.
  String _decodeBody(http.Response response) {
    final bytes = response.bodyBytes;
    final charset = _charsetOf(response.headers['content-type']);
    if (charset == 'utf-8' || charset == 'utf8') {
      return utf8.decode(bytes, allowMalformed: true);
    }
    if (charset != null && charset != 'utf-8') {
      AppLogger.debug('kazumi-rules', '未支持的响应编码 $charset，按 UTF-8 解码');
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  String? _charsetOf(String? contentType) {
    if (contentType == null) return null;
    final match = RegExp(
      r'charset\s*=\s*"?([\w-]+)"?',
      caseSensitive: false,
    ).firstMatch(contentType);
    return match?.group(1)?.toLowerCase();
  }

  String _sanitizeHeaderName(String name) =>
      name.trim().replaceAll(RegExp(r'[\r\n]'), '');

  String _sanitizeHeaderValue(Object? value) =>
      (value?.toString() ?? '').replaceAll(RegExp(r'[\r\n]'), '');

  Future<void> close() async {
    if (_ownsClient) _client.close();
  }
}
