import 'package:kazumi_rules/plugins/anti_crawler_config.dart';
import 'package:kazumi_rules/plugins/api_rule_config.dart';

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

/// A KazumiRules rule.
///
/// The nested request/search/chapter/anti-crawler configuration, plus all of
/// the parsing semantics, come from the vendored upstream package
/// (`packages/kazumi_rules`). Upstream's own `Plugin` class cannot be vendored
/// because it pulls in Dio for its search/chapter entry points, so the few
/// flat fields that `Plugin` holds are mirrored here and the nested configs
/// are parsed by upstream code.
class KazumiRule {
  /// API level implemented by the vendored parsing layer.
  ///
  /// Upstream keeps this in `lib/request/config/api_endpoints.dart`, which is
  /// outside the vendored subset. `tool/sync_kazumi_rules.ps1` fails the sync
  /// when upstream raises it, so this cannot silently go stale.
  static const supportedApiLevel = 9;

  final int apiVersion;
  final String type;
  final String name;
  final String version;
  final bool mutliSources;
  final bool usePost;
  final bool useLegacyParser;
  final bool useNativePlayer;
  final bool adBlocker;
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
  final ApiSearchConfig searchApiConfig;
  final ApiChapterConfig chapterApiConfig;
  final AntiCrawlerConfig antiCrawlerConfig;

  const KazumiRule({
    required this.apiVersion,
    required this.type,
    required this.name,
    required this.version,
    required this.mutliSources,
    required this.usePost,
    required this.useLegacyParser,
    required this.useNativePlayer,
    required this.adBlocker,
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
    required this.searchApiConfig,
    required this.chapterApiConfig,
    required this.antiCrawlerConfig,
  });

  factory KazumiRule.fromJson(Map<String, dynamic> json) {
    return KazumiRule(
      apiVersion: _asInt(json['api'], fallback: 1),
      type: json['type']?.toString().trim() ?? 'anime',
      name: json['name']?.toString().trim() ?? '',
      version: json['version']?.toString().trim() ?? '',
      mutliSources: json['muliSources'] as bool? ?? true,
      usePost: json['usePost'] as bool? ?? false,
      useLegacyParser: json['useLegacyParser'] as bool? ?? false,
      useNativePlayer: json['useNativePlayer'] as bool? ?? true,
      adBlocker: json['adBlocker'] as bool? ?? false,
      baseUrl: _parseUri(json['baseURL']),
      referer: json['referer']?.toString().trim() ?? '',
      userAgent: json['userAgent']?.toString().trim() ?? '',
      searchMode: RuleMode.normalize(json['searchMode']),
      chapterMode: RuleMode.normalize(json['chapterMode']),
      searchUrl: json['searchURL']?.toString().trim() ?? '',
      searchList: json['searchList']?.toString().trim() ?? '',
      searchName: json['searchName']?.toString().trim() ?? '',
      searchResult: json['searchResult']?.toString().trim() ?? '',
      chapterRoads: json['chapterRoads']?.toString().trim() ?? '',
      chapterResult: json['chapterResult']?.toString().trim() ?? '',
      searchApiConfig: _asMap(json['searchApiConfig']) == null
          ? ApiSearchConfig()
          : ApiSearchConfig.fromJson(_asMap(json['searchApiConfig'])!),
      chapterApiConfig: _asMap(json['chapterApiConfig']) == null
          ? ApiChapterConfig()
          : ApiChapterConfig.fromJson(_asMap(json['chapterApiConfig'])!),
      antiCrawlerConfig: _asMap(json['antiCrawlerConfig']) == null
          ? AntiCrawlerConfig.empty()
          : AntiCrawlerConfig.fromJson(_asMap(json['antiCrawlerConfig'])!),
    );
  }

  /// Short alias kept for the settings and verification dialogs.
  AntiCrawlerConfig get antiCrawler => antiCrawlerConfig;

  bool get requiresNewerClient => apiVersion > supportedApiLevel;

  /// The catalog no longer publishes this flag; withdrawn rules simply leave
  /// `index.json`. Kept so callers stay source-compatible.
  bool get deprecated => false;

  /// Fails fast with a readable message before any network call is made.
  ///
  /// Upstream reports the same problems only at parse time, where they surface
  /// to the user as a generic failure.
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
    if (searchMode == RuleMode.api) {
      if (searchApiConfig.request.url.trim().isEmpty) {
        throw const FormatException('规则缺少 API 搜索配置');
      }
    } else if (searchUrl.isEmpty ||
        searchList.isEmpty ||
        searchName.isEmpty ||
        searchResult.isEmpty) {
      throw const FormatException('规则缺少 XPath 搜索配置');
    }
    if (chapterMode == RuleMode.api) {
      if (chapterApiConfig.request.url.trim().isEmpty) {
        throw const FormatException('规则缺少 API 分集配置');
      }
    } else if (chapterRoads.isEmpty || chapterResult.isEmpty) {
      throw const FormatException('规则缺少 XPath 分集配置');
    }
  }

  void validateForApiEngine() {
    validateForRuleEngine();
    if (searchMode != RuleMode.api || chapterMode != RuleMode.api) {
      throw const FormatException('当前规则不是纯 API 模式');
    }
  }
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is! Map) return null;
  return Map<String, dynamic>.from(value);
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

int? _asIntOrNull(Object? value) {
  if (value == null) return null;
  return _asInt(value);
}
