class KazumiRuleCatalogEntry {
  final String name;
  final String version;
  final bool useNativePlayer;
  final bool antiCrawlerEnabled;
  final int? lastUpdate;

  const KazumiRuleCatalogEntry({
    required this.name,
    required this.version,
    required this.useNativePlayer,
    required this.antiCrawlerEnabled,
    this.lastUpdate,
  });

  factory KazumiRuleCatalogEntry.fromJson(Map<String, dynamic> json) {
    return KazumiRuleCatalogEntry(
      name: json['name']?.toString().trim() ?? '',
      version: json['version']?.toString().trim() ?? '',
      useNativePlayer: json['useNativePlayer'] as bool? ?? false,
      antiCrawlerEnabled: json['antiCrawlerEnabled'] as bool? ?? false,
      lastUpdate: _asIntOrNull(json['lastUpdate']),
    );
  }
}

class KazumiRule {
  static const supportedApiLevel = 8;

  final int apiVersion;
  final String type;
  final String name;
  final String version;
  final bool multipleSources;
  final bool useWebview;
  final bool useNativePlayer;
  final bool usePost;
  final bool useLegacyParser;
  final bool deprecated;
  final Uri? baseUrl;
  final String referer;
  final String userAgent;
  final String searchMode;
  final String chapterMode;
  final String searchUrl;
  final String searchList;
  final String searchName;
  final String searchResult;
  final String chapterRoads;
  final String chapterResult;
  final KazumiApiSearchConfig? searchApi;
  final KazumiApiChapterConfig? chapterApi;
  final KazumiAntiCrawlerConfig antiCrawler;

  const KazumiRule({
    required this.apiVersion,
    required this.type,
    required this.name,
    required this.version,
    required this.multipleSources,
    required this.useWebview,
    required this.useNativePlayer,
    required this.usePost,
    required this.useLegacyParser,
    required this.deprecated,
    required this.baseUrl,
    required this.referer,
    required this.userAgent,
    required this.searchMode,
    required this.chapterMode,
    required this.searchUrl,
    required this.searchList,
    required this.searchName,
    required this.searchResult,
    required this.chapterRoads,
    required this.chapterResult,
    required this.searchApi,
    required this.chapterApi,
    required this.antiCrawler,
  });

  factory KazumiRule.fromJson(Map<String, dynamic> json) {
    return KazumiRule(
      apiVersion: _asInt(json['api'], fallback: 1),
      type: json['type']?.toString().trim() ?? '',
      name: json['name']?.toString().trim() ?? '',
      version: json['version']?.toString().trim() ?? '',
      multipleSources:
          json['muliSources'] as bool? ??
          json['multiSources'] as bool? ??
          false,
      useWebview: json['useWebview'] as bool? ?? false,
      useNativePlayer: json['useNativePlayer'] as bool? ?? false,
      usePost: json['usePost'] as bool? ?? false,
      useLegacyParser: json['useLegacyParser'] as bool? ?? false,
      deprecated: json['deprecated'] as bool? ?? false,
      baseUrl: _parseUri(json['baseURL']),
      referer: json['referer']?.toString().trim() ?? '',
      userAgent: json['userAgent']?.toString().trim() ?? '',
      searchMode: _ruleMode(json['searchMode']),
      chapterMode: _ruleMode(json['chapterMode']),
      searchUrl: json['searchURL']?.toString().trim() ?? '',
      searchList: json['searchList']?.toString().trim() ?? '',
      searchName: json['searchName']?.toString().trim() ?? '',
      searchResult: json['searchResult']?.toString().trim() ?? '',
      chapterRoads: json['chapterRoads']?.toString().trim() ?? '',
      chapterResult: json['chapterResult']?.toString().trim() ?? '',
      searchApi: _asMap(json['searchApiConfig']) == null
          ? null
          : KazumiApiSearchConfig.fromJson(_asMap(json['searchApiConfig'])!),
      chapterApi: _asMap(json['chapterApiConfig']) == null
          ? null
          : KazumiApiChapterConfig.fromJson(_asMap(json['chapterApiConfig'])!),
      antiCrawler: _asMap(json['antiCrawlerConfig']) == null
          ? const KazumiAntiCrawlerConfig.disabled()
          : KazumiAntiCrawlerConfig.fromJson(
              _asMap(json['antiCrawlerConfig'])!,
            ),
    );
  }

  bool get requiresNewerClient => apiVersion > supportedApiLevel;

  void validateForRuleEngine() {
    if (requiresNewerClient) {
      throw FormatException(
        '规则需要 Kazumi API Level $apiVersion，当前支持到 Level $supportedApiLevel',
      );
    }
    if (type.isNotEmpty && type != 'anime') {
      throw FormatException('不支持的规则类型: $type');
    }
    if (name.isEmpty) throw const FormatException('规则缺少 name');
    if (!const {'api', 'xpath'}.contains(searchMode) ||
        !const {'api', 'xpath'}.contains(chapterMode)) {
      throw const FormatException('规则的搜索或分集模式无效');
    }
    if (searchMode == 'api' && searchApi == null) {
      throw const FormatException('规则缺少 API 搜索配置');
    }
    if (chapterMode == 'api' && chapterApi == null) {
      throw const FormatException('规则缺少 API 分集配置');
    }
    if (searchMode == 'xpath' &&
        (searchUrl.isEmpty ||
            searchList.isEmpty ||
            searchName.isEmpty ||
            searchResult.isEmpty)) {
      throw const FormatException('规则缺少 XPath 搜索配置');
    }
    if (chapterMode == 'xpath' &&
        (chapterRoads.isEmpty || chapterResult.isEmpty)) {
      throw const FormatException('规则缺少 XPath 分集配置');
    }
  }

  void validateForApiEngine() {
    validateForRuleEngine();
    if (searchMode != 'api' || chapterMode != 'api') {
      throw const FormatException('当前规则不是纯 API 模式');
    }
  }
}

class KazumiAntiCrawlerConfig {
  final bool enabled;
  final int captchaType;
  final String captchaImage;
  final String captchaInput;
  final String captchaButton;
  final int captchaDetectType;
  final String captchaDetectValue;
  final String captchaScript;

  const KazumiAntiCrawlerConfig({
    required this.enabled,
    required this.captchaType,
    required this.captchaImage,
    required this.captchaInput,
    required this.captchaButton,
    this.captchaDetectType = 1,
    this.captchaDetectValue = '',
    this.captchaScript = '',
  });

  const KazumiAntiCrawlerConfig.disabled()
    : enabled = false,
      captchaType = 1,
      captchaImage = '',
      captchaInput = '',
      captchaButton = '',
      captchaDetectType = 1,
      captchaDetectValue = '',
      captchaScript = '';

  factory KazumiAntiCrawlerConfig.fromJson(Map<String, dynamic> json) {
    return KazumiAntiCrawlerConfig(
      enabled: json['enabled'] as bool? ?? false,
      captchaType: _asInt(json['captchaType'], fallback: 1),
      captchaImage: json['captchaImage']?.toString() ?? '',
      captchaInput: json['captchaInput']?.toString() ?? '',
      captchaButton: json['captchaButton']?.toString() ?? '',
      captchaDetectType: _asInt(json['captchaDetectType'], fallback: 1),
      captchaDetectValue: json['captchaDetectValue']?.toString() ?? '',
      captchaScript: json['captchaScript']?.toString() ?? '',
    );
  }
}

class KazumiApiSearchConfig {
  final KazumiRuleRequest request;
  final String listPath;
  final String namePath;
  final String sourcePath;

  const KazumiApiSearchConfig({
    required this.request,
    required this.listPath,
    required this.namePath,
    required this.sourcePath,
  });

  factory KazumiApiSearchConfig.fromJson(Map<String, dynamic> json) {
    return KazumiApiSearchConfig(
      request: KazumiRuleRequest.fromJson(_asMap(json['request']) ?? const {}),
      listPath: json['listPath']?.toString().trim() ?? r'$.data[*]',
      namePath: json['namePath']?.toString().trim() ?? r'$.name',
      sourcePath: json['sourcePath']?.toString().trim() ?? r'$.url',
    );
  }
}

class KazumiApiChapterConfig {
  final KazumiRuleRequest request;
  final String format;
  final String roadsPath;
  final String roadNamePath;
  final String episodesPath;
  final String episodeNamePath;
  final String episodeUrlPath;
  final String roadNamesPath;
  final String roadEpisodesPath;
  final String roadSeparator;
  final String episodeSeparator;
  final String fieldSeparator;
  final Map<String, String> variables;
  final KazumiEpisodePage? episodePage;

  const KazumiApiChapterConfig({
    required this.request,
    required this.format,
    required this.roadsPath,
    required this.roadNamePath,
    required this.episodesPath,
    required this.episodeNamePath,
    required this.episodeUrlPath,
    required this.roadNamesPath,
    required this.roadEpisodesPath,
    required this.roadSeparator,
    required this.episodeSeparator,
    required this.fieldSeparator,
    required this.variables,
    required this.episodePage,
  });

  factory KazumiApiChapterConfig.fromJson(Map<String, dynamic> json) {
    return KazumiApiChapterConfig(
      request: KazumiRuleRequest.fromJson(_asMap(json['request']) ?? const {}),
      format: json['format']?.toString().trim().toLowerCase() ?? 'nested',
      roadsPath: json['roadsPath']?.toString().trim() ?? r'$.data.roads[*]',
      roadNamePath: json['roadNamePath']?.toString().trim() ?? r'$.name',
      episodesPath: json['episodesPath']?.toString().trim() ?? r'$.episodes[*]',
      episodeNamePath: json['episodeNamePath']?.toString().trim() ?? r'$.name',
      episodeUrlPath: json['episodeUrlPath']?.toString().trim() ?? r'$.url',
      roadNamesPath: json['roadNamesPath']?.toString().trim() ?? '',
      roadEpisodesPath: json['roadEpisodesPath']?.toString().trim() ?? '',
      roadSeparator: json['roadSeparator']?.toString() ?? r'$$$',
      episodeSeparator: json['episodeSeparator']?.toString() ?? '#',
      fieldSeparator: json['fieldSeparator']?.toString() ?? r'$',
      variables: _asStringMap(json['variables']),
      episodePage: _asMap(json['episodePage']) == null
          ? null
          : KazumiEpisodePage.fromJson(_asMap(json['episodePage'])!),
    );
  }
}

class KazumiRuleRequest {
  final String method;
  final String url;
  final Map<String, String> headers;
  final Map<String, dynamic> query;
  final String bodyType;
  final dynamic body;

  const KazumiRuleRequest({
    required this.method,
    required this.url,
    required this.headers,
    required this.query,
    required this.bodyType,
    required this.body,
  });

  factory KazumiRuleRequest.fromJson(Map<String, dynamic> json) {
    return KazumiRuleRequest(
      method: json['method']?.toString().trim().toUpperCase() ?? 'GET',
      url: json['url']?.toString().trim() ?? '',
      headers: _asStringMap(json['headers']),
      query: _asDynamicMap(json['query']),
      bodyType: json['bodyType']?.toString().trim().toLowerCase() ?? 'none',
      body: json['body'],
    );
  }
}

class KazumiEpisodePage {
  final String url;
  final Map<String, dynamic> query;

  const KazumiEpisodePage({required this.url, required this.query});

  factory KazumiEpisodePage.fromJson(Map<String, dynamic> json) {
    return KazumiEpisodePage(
      url: json['url']?.toString().trim() ?? '',
      query: _asDynamicMap(json['query']),
    );
  }
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is! Map) return null;
  return Map<String, dynamic>.from(value);
}

Map<String, dynamic> _asDynamicMap(Object? value) => _asMap(value) ?? {};

Map<String, String> _asStringMap(Object? value) {
  final map = _asMap(value);
  if (map == null) return {};
  return map.map((key, item) => MapEntry(key, item?.toString() ?? ''));
}

Uri? _parseUri(Object? value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return null;
  return Uri.tryParse(raw);
}

int _asInt(Object? value, {int fallback = 0}) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

String _ruleMode(Object? value) {
  final mode = value?.toString().trim().toLowerCase();
  return mode == 'api' ? 'api' : 'xpath';
}

int? _asIntOrNull(Object? value) {
  if (value == null) return null;
  return _asInt(value);
}
