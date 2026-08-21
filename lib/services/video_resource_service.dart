import 'package:http/http.dart' as http;

import '../models/kazumi_rule_models.dart';
import '../models/video_source_models.dart';
import 'kazumi_api_rule_engine.dart';
import 'kazumi_rules_repository.dart';

/// Coordinates KazumiRules downloads and the local rule executor.
///
/// This service intentionally exposes one rule at a time. Searching every
/// source concurrently will be added only when the UI has source selection
/// and cancellation handling.
class VideoResourceService {
  final http.Client _client;
  final KazumiRulesRepository _repository;
  final KazumiApiRuleEngine _engine;
  final bool _ownsClient;

  VideoResourceService({http.Client? client, Uri? indexUri, Uri? ruleBaseUri})
    : this._internal(
        client ?? http.Client(),
        client == null,
        indexUri: indexUri,
        ruleBaseUri: ruleBaseUri,
      );

  VideoResourceService._internal(
    this._client,
    this._ownsClient, {
    Uri? indexUri,
    Uri? ruleBaseUri,
  }) : _repository = KazumiRulesRepository(
         client: _client,
         indexUri: indexUri,
         ruleBaseUri: ruleBaseUri,
       ),
       _engine = KazumiApiRuleEngine(client: _client);

  Future<List<KazumiRuleCatalogEntry>> getRuleCatalog({
    bool forceRefresh = false,
  }) => _repository.getCatalog(forceRefresh: forceRefresh);

  Future<List<KazumiRuleCatalogEntry>> refreshRuleCatalog() =>
      _repository.refreshCatalog();

  Future<List<KazumiRule>> getInstalledRules() =>
      _repository.getInstalledRules();

  Future<KazumiRule?> getInstalledRule(String ruleName) =>
      _repository.getInstalledRule(ruleName);

  Future<KazumiRule> installRule(
    String ruleName, {
    bool forceRefresh = false,
  }) => _repository.installRule(ruleName, forceRefresh: forceRefresh);

  Future<void> uninstallRule(String ruleName) =>
      _repository.uninstallRule(ruleName);

  Future<bool> isRuleInstalled(String ruleName) =>
      _repository.isRuleInstalled(ruleName);

  Future<KazumiRule> getRule(String ruleName, {bool forceRefresh = false}) =>
      _repository.getRule(ruleName, forceRefresh: forceRefresh);

  Future<List<VideoSearchItem>> search(
    String ruleName,
    String keyword, {
    bool forceRefreshRule = false,
  }) async {
    final rule = await getRule(ruleName, forceRefresh: forceRefreshRule);
    return _engine.search(rule, keyword);
  }

  /// Uses the primary Bangumi title first and retries aliases only when the
  /// source returns nothing. This follows Kazumi's alias-search behavior
  /// without sending unnecessary requests to every site on every search.
  Future<List<VideoSearchItem>> searchWithAliases(
    String ruleName,
    Iterable<String> keywords, {
    bool forceRefreshRule = false,
  }) async {
    final rule = await getRule(ruleName, forceRefresh: forceRefreshRule);
    final candidates = <String>[];
    for (final keyword in keywords) {
      final normalized = keyword.trim();
      if (normalized.isNotEmpty && !candidates.contains(normalized)) {
        candidates.add(normalized);
      }
    }
    if (candidates.isEmpty) return const [];

    for (final keyword in candidates) {
      final results = await _engine.search(rule, keyword);
      if (results.isNotEmpty) return results;
    }
    return const [];
  }

  Future<List<VideoSearchItem>> searchRuleWithAliases(
    KazumiRule rule,
    Iterable<String> keywords,
  ) async {
    final candidates = <String>[];
    for (final keyword in keywords) {
      final normalized = keyword.trim();
      if (normalized.isNotEmpty && !candidates.contains(normalized)) {
        candidates.add(normalized);
      }
    }
    if (candidates.isEmpty) return const [];

    for (final keyword in candidates) {
      final results = await _engine.search(rule, keyword);
      if (results.isNotEmpty) return results;
    }
    return const [];
  }

  void setRuleCookieHeader(String ruleName, String cookieHeader) {
    _engine.setCookieHeader(ruleName, cookieHeader);
  }

  Future<VideoChapterResult> getChapters(
    KazumiRule rule,
    VideoSearchItem item,
  ) => _engine.getChapters(rule, item);

  Future<VideoChapterResult> getChaptersByRule(
    String ruleName,
    VideoSearchItem item, {
    bool forceRefreshRule = false,
  }) async {
    final rule = await getRule(ruleName, forceRefresh: forceRefreshRule);
    return getChapters(rule, item);
  }

  void clearRuleCache() => _repository.clearCache();

  Future<void> close() async {
    await _repository.close();
    await _engine.close();
    if (_ownsClient) _client.close();
  }
}
