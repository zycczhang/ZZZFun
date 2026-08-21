import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/kazumi_rule_models.dart';
import 'app_logger.dart';

class KazumiRulesException implements Exception {
  final String message;
  final int? statusCode;
  final Object? cause;

  const KazumiRulesException(this.message, {this.statusCode, this.cause});

  @override
  String toString() {
    final status = statusCode == null ? '' : ' ($statusCode)';
    final detail = cause == null ? '' : ': $cause';
    return 'KazumiRulesException$status: $message$detail';
  }
}

class KazumiRulesRepository {
  static const _catalogStorageKey = 'zzzfun_kazumi_rule_catalog_v1';
  static const _installedStorageKey = 'zzzfun_kazumi_installed_rules_v1';
  static final _defaultIndexUri = Uri.parse(
    'https://raw.githubusercontent.com/Predidit/KazumiRules/main/index.json',
  );
  static final _defaultRuleBaseUri = Uri.parse(
    'https://raw.githubusercontent.com/Predidit/KazumiRules/main/',
  );
  static final _fallbackIndexUri = Uri.parse(
    'https://cdn.jsdelivr.net/gh/Predidit/KazumiRules@main/index.json',
  );
  static final _fallbackRuleBaseUri = Uri.parse(
    'https://cdn.jsdelivr.net/gh/Predidit/KazumiRules@main/',
  );

  final http.Client _client;
  final Uri _indexUri;
  final Uri _ruleBaseUri;
  final Uri? _indexFallbackUri;
  final Uri? _ruleFallbackBaseUri;
  final Duration _timeout;
  final bool _ownsClient;
  final bool _persistenceEnabled;
  Future<SharedPreferences>? _preferencesFuture;
  List<KazumiRuleCatalogEntry>? _catalogCache;
  final Map<String, KazumiRule> _ruleCache = {};
  Map<String, Map<String, dynamic>>? _installedPayloads;

  KazumiRulesRepository({
    http.Client? client,
    Uri? indexUri,
    Uri? ruleBaseUri,
    Duration timeout = const Duration(seconds: 15),
    bool persistenceEnabled = true,
  }) : _client = client ?? http.Client(),
       _indexUri = indexUri ?? _defaultIndexUri,
       _ruleBaseUri = ruleBaseUri ?? _defaultRuleBaseUri,
       _indexFallbackUri = indexUri == null ? _fallbackIndexUri : null,
       _ruleFallbackBaseUri = ruleBaseUri == null ? _fallbackRuleBaseUri : null,
       _timeout = timeout,
       _ownsClient = client == null,
       _persistenceEnabled = persistenceEnabled;

  Future<List<KazumiRuleCatalogEntry>> getCatalog({
    bool forceRefresh = false,
  }) async {
    _catalogCache ??= await _readCatalogCache();
    if (!forceRefresh && _catalogCache != null) return _catalogCache!;
    try {
      final response = await _request(
        '获取 KazumiRules 索引',
        _indexUri,
        fallback: _indexFallbackUri,
      );
      final decoded = _decodeList(response);
      final catalog = decoded
          .map(KazumiRuleCatalogEntry.fromJson)
          .where((item) => item.name.isNotEmpty)
          .toList(growable: false);
      _catalogCache = catalog;
      await _writeCatalogCache(catalog);
      return catalog;
    } catch (_) {
      if (_catalogCache != null) return _catalogCache!;
      rethrow;
    }
  }

  /// Fetches the remote catalog without falling back to the cached copy.
  ///
  /// This is used by the settings page's explicit update check so a failed
  /// network request is not reported as a successful check against stale data.
  Future<List<KazumiRuleCatalogEntry>> refreshCatalog() async {
    final response = await _request(
      '获取 KazumiRules 索引',
      _indexUri,
      fallback: _indexFallbackUri,
    );
    final decoded = _decodeList(response);
    final catalog = decoded
        .map(KazumiRuleCatalogEntry.fromJson)
        .where((item) => item.name.isNotEmpty)
        .toList(growable: false);
    _catalogCache = catalog;
    await _writeCatalogCache(catalog);
    return catalog;
  }

  Future<KazumiRule> getRule(String name, {bool forceRefresh = false}) async {
    final normalizedName = name.trim();
    _validateRuleName(normalizedName);
    if (!forceRefresh && _ruleCache.containsKey(normalizedName)) {
      return _ruleCache[normalizedName]!;
    }

    final decoded = await _fetchRulePayload(normalizedName);
    final rule = KazumiRule.fromJson(decoded);
    if (rule.name.isEmpty) {
      throw const KazumiRulesException('规则缺少有效 name');
    }
    _ruleCache[normalizedName] = rule;
    return rule;
  }

  /// Downloads a rule and makes it available to the player.
  ///
  /// The downloaded JSON is kept locally, so playback does not depend on
  /// GitHub being reachable every time a detail page is opened.
  Future<KazumiRule> installRule(
    String name, {
    bool forceRefresh = false,
  }) async {
    final normalizedName = name.trim();
    _validateRuleName(normalizedName);
    final decoded = await _fetchRulePayload(
      normalizedName,
      forceRefresh: forceRefresh,
    );
    final rule = KazumiRule.fromJson(decoded);
    if (rule.name.isEmpty) {
      throw const KazumiRulesException('规则缺少有效 name');
    }
    _ruleCache[normalizedName] = rule;
    final payloads = await _loadInstalledPayloads();
    payloads[normalizedName] = decoded;
    await _writeInstalledPayloads(payloads);
    AppLogger.info('kazumi-rules', '规则已安装: $normalizedName ${rule.version}');
    return rule;
  }

  Future<void> uninstallRule(String name) async {
    final normalizedName = name.trim();
    _validateRuleName(normalizedName);
    final payloads = await _loadInstalledPayloads();
    if (payloads.remove(normalizedName) == null) return;
    _ruleCache.remove(normalizedName);
    await _writeInstalledPayloads(payloads);
    AppLogger.info('kazumi-rules', '规则已删除: $normalizedName');
  }

  Future<bool> isRuleInstalled(String name) async {
    final normalizedName = name.trim();
    _validateRuleName(normalizedName);
    final payloads = await _loadInstalledPayloads();
    return payloads.containsKey(normalizedName);
  }

  Future<KazumiRule?> getInstalledRule(String name) async {
    final normalizedName = name.trim();
    _validateRuleName(normalizedName);
    final payloads = await _loadInstalledPayloads();
    final payload = payloads[normalizedName];
    if (payload == null) return null;
    try {
      return KazumiRule.fromJson(payload);
    } on FormatException catch (error, stackTrace) {
      AppLogger.warning(
        'kazumi-rules',
        '本地规则 $normalizedName 无法读取',
        error,
        stackTrace,
      );
      return null;
    }
  }

  Future<List<KazumiRule>> getInstalledRules() async {
    final payloads = await _loadInstalledPayloads();
    final rules = <KazumiRule>[];
    for (final entry in payloads.entries) {
      try {
        final rule = KazumiRule.fromJson(entry.value);
        if (rule.name.isNotEmpty) rules.add(rule);
      } on FormatException catch (error, stackTrace) {
        AppLogger.warning(
          'kazumi-rules',
          '跳过无效的本地规则 ${entry.key}',
          error,
          stackTrace,
        );
      }
    }
    rules.sort((left, right) => left.name.compareTo(right.name));
    return rules;
  }

  void clearCache() {
    _catalogCache = null;
    _ruleCache.clear();
  }

  Future<Map<String, dynamic>> _fetchRulePayload(
    String normalizedName, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final payloads = await _loadInstalledPayloads();
      final installedPayload = payloads[normalizedName];
      if (installedPayload != null) return installedPayload;
    }
    final response = await _request(
      '获取规则 $normalizedName',
      _ruleBaseUri.resolve('$normalizedName.json'),
      fallback: _ruleFallbackBaseUri?.resolve('$normalizedName.json'),
    );
    return _decodeMap(response);
  }

  Future<dynamic> _request(String operation, Uri uri, {Uri? fallback}) async {
    Object? lastError;
    StackTrace? lastStackTrace;
    final candidates = [uri, if (fallback != null && fallback != uri) fallback];
    for (final candidate in candidates) {
      try {
        return await _requestOnce(operation, candidate);
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
      }
    }

    try {
      if (lastError is KazumiRulesException) throw lastError;
      if (lastError is TimeoutException) throw lastError;
      throw lastError ?? const KazumiRulesException('未知网络错误');
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
      AppLogger.warning(
        'kazumi-rules',
        exception.message,
        error,
        lastStackTrace ?? stackTrace,
      );
      throw exception;
    }
  }

  Future<dynamic> _requestOnce(String operation, Uri uri) async {
    final response = await _client
        .get(uri, headers: _headers())
        .timeout(_timeout);
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
  }

  Future<Map<String, Map<String, dynamic>>> _loadInstalledPayloads() async {
    if (_installedPayloads != null) return _installedPayloads!;
    if (!_persistenceEnabled) return _installedPayloads = {};
    try {
      final prefs = await _preferences();
      final raw = prefs.getString(_installedStorageKey);
      if (raw == null || raw.isEmpty) return _installedPayloads = {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return _installedPayloads = {};
      _installedPayloads = {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is Map)
            entry.key.toString(): Map<String, dynamic>.from(entry.value as Map),
      };
    } catch (error, stackTrace) {
      AppLogger.warning('kazumi-rules', '读取本地规则失败', error, stackTrace);
      _installedPayloads = {};
    }
    return _installedPayloads!;
  }

  Future<List<KazumiRuleCatalogEntry>?> _readCatalogCache() async {
    if (!_persistenceEnabled) return null;
    try {
      final prefs = await _preferences();
      final raw = prefs.getString(_catalogStorageKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded
          .whereType<Map>()
          .map(
            (item) => KazumiRuleCatalogEntry.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where((item) => item.name.isNotEmpty)
          .toList(growable: false);
    } catch (error, stackTrace) {
      AppLogger.warning('kazumi-rules', '读取规则索引缓存失败', error, stackTrace);
      return null;
    }
  }

  Future<void> _writeCatalogCache(List<KazumiRuleCatalogEntry> catalog) async {
    if (!_persistenceEnabled) return;
    try {
      final prefs = await _preferences();
      await prefs.setString(
        _catalogStorageKey,
        jsonEncode(catalog.map(_catalogToJson).toList()),
      );
    } catch (error, stackTrace) {
      AppLogger.warning('kazumi-rules', '保存规则索引缓存失败', error, stackTrace);
    }
  }

  Future<void> _writeInstalledPayloads(
    Map<String, Map<String, dynamic>> payloads,
  ) async {
    _installedPayloads = payloads;
    if (!_persistenceEnabled) return;
    try {
      final prefs = await _preferences();
      await prefs.setString(_installedStorageKey, jsonEncode(payloads));
    } catch (error, stackTrace) {
      AppLogger.warning('kazumi-rules', '保存本地规则失败', error, stackTrace);
    }
  }

  Future<SharedPreferences> _preferences() {
    return _preferencesFuture ??= SharedPreferences.getInstance();
  }

  Map<String, dynamic> _catalogToJson(KazumiRuleCatalogEntry entry) => {
    'name': entry.name,
    'version': entry.version,
    'useNativePlayer': entry.useNativePlayer,
    'antiCrawlerEnabled': entry.antiCrawlerEnabled,
    if (entry.lastUpdate != null) 'lastUpdate': entry.lastUpdate,
  };

  Map<String, String> _headers() => {
    'Accept': 'application/json',
    'User-Agent': 'ZZZFun/1.0',
  };

  List<Map<String, dynamic>> _decodeList(Object? value) {
    if (value is! List) {
      throw const KazumiRulesException('规则索引不是 JSON 数组');
    }
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Map<String, dynamic> _decodeMap(Object? value) {
    if (value is! Map) {
      throw const KazumiRulesException('规则文件不是 JSON 对象');
    }
    return Map<String, dynamic>.from(value);
  }

  void _validateRuleName(String name) {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(name)) {
      throw const KazumiRulesException('规则名称包含不允许的字符');
    }
  }

  Future<void> close() async {
    if (_ownsClient) _client.close();
  }
}
