import 'dart:async';
import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';

import '../models/kazumi_rule_models.dart';
import '../models/video_source_models.dart';
import 'app_logger.dart';
import 'json_path_service.dart';
import 'kazumi_rules_repository.dart';

class KazumiCaptchaRequiredException implements Exception {
  final String ruleName;
  final String url;

  const KazumiCaptchaRequiredException(this.ruleName, this.url);

  @override
  String toString() => 'KazumiCaptchaRequiredException: $ruleName';
}

class KazumiApiRuleEngine {
  static const _defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/141.0.0.0 Safari/537.36';
  static const _defaultAcceptLanguage = 'zh-CN,zh;q=0.9';

  final http.Client _client;
  final Duration _timeout;
  final JsonPathService _jsonPath;
  final bool _ownsClient;
  final Map<String, String> _cookieHeaders = {};

  KazumiApiRuleEngine({
    http.Client? client,
    Duration timeout = const Duration(seconds: 15),
    JsonPathService jsonPath = const JsonPathService(),
  }) : _client = client ?? http.Client(),
       _timeout = timeout,
       _jsonPath = jsonPath,
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
    if (rule.searchMode == 'xpath') {
      return _searchXPath(rule, keyword);
    }
    return _searchApi(rule, keyword);
  }

  Future<List<VideoSearchItem>> _searchApi(
    KazumiRule rule,
    String keyword,
  ) async {
    rule.validateForRuleEngine();
    if (rule.searchMode != 'api' || rule.searchApi == null) {
      throw const FormatException('规则缺少 API 搜索配置');
    }
    final config = rule.searchApi!;
    final response = await _requestJson(
      rule,
      '搜索 ${rule.name}',
      config.request,
      {'keyword': keyword.trim()},
    );
    final rows = _jsonPath.readList(response, config.listPath);
    final results = <VideoSearchItem>[];
    for (final row in rows) {
      final name = _stringValue(_readPath(row, config.namePath));
      final source = _stringValue(_readPath(row, config.sourcePath));
      if (name.isEmpty || source.isEmpty) continue;
      results.add(
        VideoSearchItem(name: name, source: source, ruleName: rule.name),
      );
    }
    return results;
  }

  Future<VideoChapterResult> getChapters(
    KazumiRule rule,
    VideoSearchItem item,
  ) async {
    rule.validateForRuleEngine();
    if (rule.chapterMode == 'xpath') {
      return _getXPathChapters(rule, item);
    }
    return _getApiChapters(rule, item);
  }

  Future<VideoChapterResult> _getApiChapters(
    KazumiRule rule,
    VideoSearchItem item,
  ) async {
    rule.validateForRuleEngine();
    if (rule.chapterMode != 'api' || rule.chapterApi == null) {
      throw const FormatException('规则缺少 API 分集配置');
    }
    if (item.ruleName != rule.name) {
      throw KazumiRulesException('搜索结果与规则不匹配');
    }
    final config = rule.chapterApi!;
    final context = <String, dynamic>{'source': item.source};
    final response = await _requestJson(
      rule,
      '获取 ${rule.name} 分集',
      config.request,
      context,
    );

    if (config.format == 'delimited') {
      return _getDelimitedApiChapters(rule, item, config, response, context);
    }

    final rootVariables = <String, dynamic>{};
    for (final entry in config.variables.entries) {
      rootVariables[entry.key] =
          _jsonPath.readFirst(response, entry.value) ?? '';
    }

    if (config.format.isNotEmpty && config.format != 'nested') {
      throw FormatException('暂不支持的 API 分集格式: ${config.format}');
    }
    final roadRows = config.roadsPath.trim().isEmpty
        ? <Object?>[response]
        : _jsonPath.readList(response, config.roadsPath);
    final sources = <VideoSource>[];
    for (var roadIndex = 0; roadIndex < roadRows.length; roadIndex++) {
      final road = roadRows[roadIndex];
      final roadName = _stringValue(_readPath(road, config.roadNamePath));
      final episodeRows = _jsonPath.readList(road, config.episodesPath);
      final episodes = <VideoEpisode>[];
      for (
        var episodeIndex = 0;
        episodeIndex < episodeRows.length;
        episodeIndex++
      ) {
        final episode = episodeRows[episodeIndex];
        final episodeName = _stringValue(
          _readPath(episode, config.episodeNamePath),
        );
        final episodeUrl = _stringValue(
          _readPath(episode, config.episodeUrlPath),
        );
        final episodeContext = <String, dynamic>{
          ...context,
          ...rootVariables,
          'roadIndex': roadIndex,
          'roadNumber': roadIndex + 1,
          'episodeIndex': episodeIndex,
          'episodeNumber': episodeIndex + 1,
          'episodeUrl': episodeUrl,
        };
        final pageUrl = _buildEpisodePageUrl(
          rule,
          config.episodePage,
          episodeContext,
          episodeUrl,
        );
        if (pageUrl.isEmpty) continue;
        episodes.add(
          VideoEpisode(
            name: episodeName.isEmpty ? '第${episodeIndex + 1}集' : episodeName,
            pageUrl: pageUrl,
            roadIndex: roadIndex,
            episodeIndex: episodeIndex,
            requestHeaders: _pageHeaders(rule),
            useLegacyParser: rule.useLegacyParser,
          ),
        );
      }
      if (episodes.isNotEmpty) {
        sources.add(
          VideoSource(
            name: roadName.isEmpty ? '线路 ${roadIndex + 1}' : roadName,
            episodes: episodes,
          ),
        );
      }
    }
    return VideoChapterResult(
      ruleName: rule.name,
      source: item.source,
      sources: sources,
    );
  }

  VideoChapterResult _getDelimitedApiChapters(
    KazumiRule rule,
    VideoSearchItem item,
    KazumiApiChapterConfig config,
    dynamic response,
    Map<String, dynamic> context,
  ) {
    if (config.roadSeparator.isEmpty ||
        config.episodeSeparator.isEmpty ||
        config.fieldSeparator.isEmpty) {
      throw const FormatException('API 分集分隔符不能为空');
    }
    final roadNamesValue = _stringValue(
      _readPath(response, config.roadNamesPath),
    );
    final roadEpisodesValue = _stringValue(
      _readPath(response, config.roadEpisodesPath),
    );
    if (roadEpisodesValue.isEmpty) {
      return VideoChapterResult(
        ruleName: rule.name,
        source: item.source,
        sources: const [],
      );
    }

    final roadNames = roadNamesValue.split(config.roadSeparator);
    final roadGroups = roadEpisodesValue.split(config.roadSeparator);
    final rootVariables = <String, dynamic>{...context};
    for (final entry in config.variables.entries) {
      rootVariables[entry.key] =
          _jsonPath.readFirst(response, entry.value) ?? '';
    }
    final sources = <VideoSource>[];
    for (var roadIndex = 0; roadIndex < roadGroups.length; roadIndex++) {
      final episodes = <VideoEpisode>[];
      final entries = roadGroups[roadIndex].split(config.episodeSeparator);
      for (
        var episodeIndex = 0;
        episodeIndex < entries.length;
        episodeIndex++
      ) {
        final entry = entries[episodeIndex].trim();
        if (entry.isEmpty) continue;
        final separatorIndex = entry.indexOf(config.fieldSeparator);
        if (separatorIndex < 0) continue;
        final episodeName = entry.substring(0, separatorIndex).trim();
        final episodeUrl = entry
            .substring(separatorIndex + config.fieldSeparator.length)
            .trim();
        final episodeContext = <String, dynamic>{
          ...rootVariables,
          'roadIndex': roadIndex,
          'roadNumber': roadIndex + 1,
          'episodeIndex': episodeIndex,
          'episodeNumber': episodeIndex + 1,
          'episodeUrl': episodeUrl,
        };
        final pageUrl = _buildEpisodePageUrl(
          rule,
          config.episodePage,
          episodeContext,
          episodeUrl,
        );
        if (pageUrl.isEmpty) continue;
        episodes.add(
          VideoEpisode(
            name: episodeName.isEmpty ? '第${episodeIndex + 1}集' : episodeName,
            pageUrl: pageUrl,
            roadIndex: roadIndex,
            episodeIndex: episodeIndex,
            requestHeaders: _pageHeaders(rule),
            useLegacyParser: rule.useLegacyParser,
          ),
        );
      }
      if (episodes.isNotEmpty) {
        sources.add(
          VideoSource(
            name:
                roadIndex < roadNames.length &&
                    roadNames[roadIndex].trim().isNotEmpty
                ? roadNames[roadIndex].trim()
                : '线路 ${roadIndex + 1}',
            episodes: episodes,
          ),
        );
      }
    }
    return VideoChapterResult(
      ruleName: rule.name,
      source: item.source,
      sources: sources,
    );
  }

  Future<List<VideoSearchItem>> _searchXPath(
    KazumiRule rule,
    String keyword,
  ) async {
    final searchUrl = rule.searchUrl.replaceAll(
      '@keyword',
      Uri.encodeQueryComponent(keyword.trim()),
    );
    final parsedUrl = Uri.tryParse(searchUrl);
    if (parsedUrl == null || !parsedUrl.hasScheme || parsedUrl.host.isEmpty) {
      throw FormatException('规则搜索 URL 无效: $searchUrl');
    }

    String method = 'GET';
    Uri requestUrl = parsedUrl;
    String? body;
    if (rule.usePost) {
      method = 'POST';
      final query = parsedUrl.queryParameters;
      requestUrl = parsedUrl.replace(queryParameters: const {});
      body = query.entries
          .map(
            (entry) =>
                '${Uri.encodeQueryComponent(entry.key)}='
                '${Uri.encodeQueryComponent(entry.value)}',
          )
          .join('&');
    }

    final raw = await _requestHtml(
      rule,
      '搜索 ${rule.name}',
      requestUrl,
      method: method,
      body: body,
    );
    final root = _parseHtmlRoot(raw);
    if (_isCaptchaPage(rule, raw, root)) {
      throw KazumiCaptchaRequiredException(rule.name, searchUrl);
    }
    final nodes = _runXPath(rule.searchList, root, '搜索结果列表');
    final results = <VideoSearchItem>[];
    for (var index = 0; index < nodes.length; index++) {
      final node = nodes[index];
      try {
        final nameNode = _runXPathNode(rule.searchName, node, '搜索结果名称');
        final resultNode = _runXPathNode(rule.searchResult, node, '搜索结果链接');
        final name = nameNode?.text?.trim() ?? '';
        final source = resultNode?.attributes['href']?.trim() ?? '';
        if (name.isEmpty || source.isEmpty) continue;
        results.add(
          VideoSearchItem(
            name: name,
            source: _resolveUrl(rule, source),
            ruleName: rule.name,
          ),
        );
      } catch (error) {
        AppLogger.warning(
          'kazumi-rules',
          '${rule.name} 搜索结果 $index 解析失败',
          error,
        );
      }
    }
    return results;
  }

  Future<VideoChapterResult> _getXPathChapters(
    KazumiRule rule,
    VideoSearchItem item,
  ) async {
    if (item.ruleName != rule.name) {
      throw KazumiRulesException('搜索结果与规则不匹配');
    }
    final chapterUrl = Uri.tryParse(_resolveUrl(rule, item.source));
    if (chapterUrl == null ||
        !chapterUrl.hasScheme ||
        chapterUrl.host.isEmpty) {
      throw FormatException('规则分集 URL 无效: ${item.source}');
    }
    final raw = await _requestHtml(rule, '获取 ${rule.name} 分集', chapterUrl);
    final root = _parseHtmlRoot(raw);
    final roadNodes = _runXPath(rule.chapterRoads, root, '播放线路列表');
    final sources = <VideoSource>[];
    for (var roadIndex = 0; roadIndex < roadNodes.length; roadIndex++) {
      final roadNode = roadNodes[roadIndex];
      final episodeNodes = _runXPath(rule.chapterResult, roadNode, '剧集列表');
      final episodes = <VideoEpisode>[];
      for (
        var episodeIndex = 0;
        episodeIndex < episodeNodes.length;
        episodeIndex++
      ) {
        final episodeNode = episodeNodes[episodeIndex];
        final source = episodeNode.attributes['href']?.trim() ?? '';
        if (source.isEmpty) continue;
        final name = (episodeNode.text ?? '').replaceAll(RegExp(r'\s+'), '');
        episodes.add(
          VideoEpisode(
            name: name.isEmpty ? '第${episodeIndex + 1}集' : name,
            pageUrl: _resolveUrl(rule, source),
            roadIndex: roadIndex,
            episodeIndex: episodeIndex,
            requestHeaders: _pageHeaders(rule),
            useLegacyParser: rule.useLegacyParser,
          ),
        );
      }
      if (episodes.isNotEmpty) {
        sources.add(
          VideoSource(name: '播放线路${sources.length + 1}', episodes: episodes),
        );
      }
    }
    return VideoChapterResult(
      ruleName: rule.name,
      source: item.source,
      sources: sources,
    );
  }

  Element _parseHtmlRoot(String raw) {
    try {
      final root = html_parser.parse(raw).documentElement;
      if (root == null) throw const FormatException('HTML 没有根节点');
      return root;
    } catch (error) {
      if (error is FormatException) rethrow;
      throw FormatException('HTML 解析失败: $error');
    }
  }

  bool _isCaptchaPage(KazumiRule rule, String raw, Element root) {
    final config = rule.antiCrawler;
    if (!config.enabled) return false;
    final detectValue = config.captchaDetectValue.trim();
    if (detectValue.isNotEmpty) {
      switch (config.captchaDetectType) {
        case 2:
          return raw.contains(detectValue);
        case 3:
          try {
            return RegExp(
              detectValue,
              caseSensitive: false,
              dotAll: true,
            ).hasMatch(raw);
          } on FormatException {
            return false;
          }
        case 1:
        default:
          try {
            return _runXPath(detectValue, root, '验证页检测').isNotEmpty;
          } on FormatException {
            return false;
          }
      }
    }
    for (final expression in [config.captchaImage, config.captchaButton]) {
      if (expression.trim().isEmpty) continue;
      try {
        if (_runXPath(expression, root, '验证元素检测').isNotEmpty) return true;
      } on FormatException {
        // A malformed optional fallback selector should not block normal search.
      }
    }
    return false;
  }

  List<dynamic> _runXPath(String expression, Object root, String label) {
    if (expression.trim().isEmpty) {
      throw FormatException('$label XPath 不能为空');
    }
    try {
      final result = root is Element
          ? HtmlXPath.node(root).query(expression)
          : (root as dynamic).queryXPath(expression);
      return List<dynamic>.from(result.nodes);
    } catch (error) {
      throw FormatException('$label XPath 无效: $expression ($error)');
    }
  }

  dynamic _runXPathNode(String expression, Object root, String label) {
    final nodes = _runXPath(expression, root, label);
    return nodes.isEmpty ? null : nodes.first;
  }

  String _resolveUrl(KazumiRule rule, String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    final parsed = Uri.tryParse(value);
    if (parsed?.hasScheme == true) return parsed!.toString();
    final base = rule.baseUrl;
    if (base != null) return base.resolve(value).toString();
    return value;
  }

  Future<String> _requestHtml(
    KazumiRule rule,
    String operation,
    Uri uri, {
    String method = 'GET',
    String? body,
  }) async {
    final headers = <String, String>{
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': _defaultAcceptLanguage,
      'Connection': 'keep-alive',
      'User-Agent': rule.userAgent.isEmpty ? _defaultUserAgent : rule.userAgent,
      if (rule.referer.isNotEmpty)
        'Referer': rule.referer
      else if (rule.baseUrl != null)
        'Referer': rule.baseUrl.toString(),
      if (_cookieHeaders[rule.name]?.isNotEmpty == true)
        'Cookie': _cookieHeaders[rule.name]!,
      if (method == 'POST') 'Content-Type': 'application/x-www-form-urlencoded',
    };
    try {
      final response = await _send(
        method,
        uri,
        headers,
        body,
      ).timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw KazumiRulesException(
          '$operation请求失败',
          statusCode: response.statusCode,
        );
      }
      return utf8.decode(response.bodyBytes);
    } on KazumiRulesException catch (error, stackTrace) {
      AppLogger.warning('kazumi-rules', error.message, error, stackTrace);
      rethrow;
    } on TimeoutException catch (error, stackTrace) {
      final exception = KazumiRulesException('$operation超时', cause: error);
      AppLogger.warning(
        'kazumi-rules',
        exception.message,
        exception,
        stackTrace,
      );
      throw exception;
    } catch (error, stackTrace) {
      final exception = KazumiRulesException('$operation失败', cause: error);
      AppLogger.warning('kazumi-rules', exception.message, error, stackTrace);
      throw exception;
    }
  }

  Future<dynamic> _requestJson(
    KazumiRule rule,
    String operation,
    KazumiRuleRequest request,
    Map<String, dynamic> context,
  ) async {
    final uri = _buildUri(rule, request.url, request.query, context);
    final headers = <String, String>{
      'Accept': 'application/json',
      'Accept-Language': _defaultAcceptLanguage,
      'Connection': 'keep-alive',
      'User-Agent': rule.userAgent.isEmpty ? _defaultUserAgent : rule.userAgent,
      if (rule.referer.isNotEmpty)
        'Referer': rule.referer
      else if (rule.baseUrl != null)
        'Referer': rule.baseUrl.toString(),
      if (_cookieHeaders[rule.name]?.isNotEmpty == true)
        'Cookie': _cookieHeaders[rule.name]!,
      ...request.headers.map(
        (key, value) => MapEntry(key, _expandString(value, context)),
      ),
    };
    final method = request.method.isEmpty ? 'GET' : request.method;
    final body = _buildBody(request, context, headers);

    try {
      final response = await _send(
        method,
        uri,
        headers,
        body,
      ).timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw KazumiRulesException(
          '$operation请求失败',
          statusCode: response.statusCode,
        );
      }
      try {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException catch (error) {
        throw KazumiRulesException('$operation返回了无效 JSON', cause: error);
      }
    } on KazumiRulesException catch (error, stackTrace) {
      AppLogger.warning('kazumi-rules', error.message, error, stackTrace);
      rethrow;
    } on TimeoutException catch (error, stackTrace) {
      final exception = KazumiRulesException('$operation超时', cause: error);
      AppLogger.warning(
        'kazumi-rules',
        exception.message,
        exception,
        stackTrace,
      );
      throw exception;
    } catch (error, stackTrace) {
      final exception = KazumiRulesException('$operation失败', cause: error);
      AppLogger.warning('kazumi-rules', exception.message, error, stackTrace);
      throw exception;
    }
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
      case 'PUT':
        return _client.put(uri, headers: headers, body: body);
      case 'DELETE':
        return _client.delete(uri, headers: headers, body: body);
      default:
        throw KazumiRulesException('不支持的规则请求方法: $method');
    }
  }

  Uri _buildUri(
    KazumiRule rule,
    String rawUrl,
    Map<String, dynamic> query,
    Map<String, dynamic> context,
  ) {
    if (rawUrl.trim().isEmpty) {
      throw const KazumiRulesException('规则请求 URL 不能为空');
    }
    final expandedUrl = _expandString(rawUrl, context, encode: true);
    final base = rule.baseUrl;
    final parsed = Uri.tryParse(expandedUrl);
    final resolved = parsed?.hasScheme == true
        ? parsed!
        : base?.resolve(expandedUrl) ?? Uri.parse(expandedUrl);
    _validateHttpUri(resolved);
    final expandedQuery = _expandMap(query, context);
    if (expandedQuery.isEmpty) return resolved;
    return resolved.replace(
      queryParameters: {
        ...resolved.queryParameters,
        ...expandedQuery.map(
          (key, value) => MapEntry(key, _stringValue(value)),
        ),
      },
    );
  }

  String? _buildBody(
    KazumiRuleRequest request,
    Map<String, dynamic> context,
    Map<String, String> headers,
  ) {
    if (request.body == null) return null;
    final body = _expandValue(request.body, context);
    switch (request.bodyType) {
      case 'form':
      case 'formdata':
      case 'x-www-form-urlencoded':
        headers.putIfAbsent(
          'Content-Type',
          () => 'application/x-www-form-urlencoded',
        );
        if (body is Map) {
          return body.entries
              .map(
                (entry) =>
                    '${Uri.encodeQueryComponent(entry.key.toString())}='
                    '${Uri.encodeQueryComponent(_stringValue(entry.value))}',
              )
              .join('&');
        }
        return body.toString();
      case 'none':
        return null;
      case 'json':
      case '':
        headers.putIfAbsent('Content-Type', () => 'application/json');
        return jsonEncode(body);
      default:
        throw KazumiRulesException('不支持的规则 bodyType: ${request.bodyType}');
    }
  }

  String _buildEpisodePageUrl(
    KazumiRule rule,
    KazumiEpisodePage? page,
    Map<String, dynamic> context,
    String episodeUrl,
  ) {
    if (page == null || page.url.isEmpty) {
      final resolved = _resolveUrl(rule, episodeUrl);
      final parsed = Uri.tryParse(resolved);
      if (parsed == null || !parsed.hasScheme) return '';
      _validateHttpUri(parsed);
      return parsed.toString();
    }
    final expandedUrl = _expandString(page.url, context, encode: true);
    final parsed = Uri.tryParse(expandedUrl);
    final resolved = parsed?.hasScheme == true
        ? parsed!
        : rule.baseUrl?.resolve(expandedUrl) ?? Uri.parse(expandedUrl);
    _validateHttpUri(resolved);
    final query = _expandMap(page.query, context);
    return query.isEmpty
        ? resolved.toString()
        : resolved
              .replace(
                queryParameters: {
                  ...resolved.queryParameters,
                  ...query.map(
                    (key, value) => MapEntry(key, _stringValue(value)),
                  ),
                },
              )
              .toString();
  }

  Map<String, String> _pageHeaders(KazumiRule rule) => {
    'User-Agent': rule.userAgent.isEmpty ? _defaultUserAgent : rule.userAgent,
    if (rule.referer.isNotEmpty)
      'Referer': rule.referer
    else if (rule.baseUrl != null)
      'Referer': rule.baseUrl.toString(),
  };

  Map<String, dynamic> _expandMap(
    Map<String, dynamic> values,
    Map<String, dynamic> context,
  ) => values.map((key, value) => MapEntry(key, _expandValue(value, context)));

  dynamic _expandValue(dynamic value, Map<String, dynamic> context) {
    if (value is String) {
      final exact = RegExp(r'^@([A-Za-z][A-Za-z0-9_]*)$').firstMatch(value);
      if (exact != null && context.containsKey(exact.group(1))) {
        return context[exact.group(1)];
      }
      return _expandString(value, context);
    }
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key.toString(), _expandValue(item, context)),
      );
    }
    if (value is List) {
      return value.map((item) => _expandValue(item, context)).toList();
    }
    return value;
  }

  String _expandString(
    String value,
    Map<String, dynamic> context, {
    bool encode = false,
  }) {
    var result = value;
    final keys = context.keys.toList()
      ..sort((left, right) => right.length.compareTo(left.length));
    for (final key in keys) {
      final replacement = _stringValue(context[key]);
      result = result.replaceAll(
        '@$key',
        encode ? Uri.encodeComponent(replacement) : replacement,
      );
    }
    return result;
  }

  String _stringValue(Object? value) {
    if (value == null) return '';
    if (value is String) return value.trim();
    return value.toString().trim();
  }

  Object? _readPath(Object? root, String path) {
    final normalizedPath = path.trim();
    if (normalizedPath.isEmpty) return null;
    return _jsonPath.readFirst(root, normalizedPath);
  }

  void _validateHttpUri(Uri uri) {
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw KazumiRulesException('规则地址不是 HTTP(S) 地址: $uri');
    }
  }

  Future<void> close() async {
    if (_ownsClient) _client.close();
  }
}
