import 'dart:async';

import 'package:flutter/material.dart';

import '../anime_nav_widgets.dart';
import '../models/anime_models.dart';
import '../models/kazumi_rule_models.dart';
import '../models/video_source_models.dart';
import '../services/kazumi_api_rule_engine.dart';
import '../services/video_resource_service.dart';
import 'kazumi_captcha_dialog.dart';

class VideoSourcePickerDialog extends StatefulWidget {
  final AnimeItem item;
  final VideoResourceService resourceService;

  const VideoSourcePickerDialog({
    super.key,
    required this.item,
    required this.resourceService,
  });

  @override
  State<VideoSourcePickerDialog> createState() =>
      _VideoSourcePickerDialogState();
}

class _VideoSourcePickerDialogState extends State<VideoSourcePickerDialog> {
  final Map<String, VideoRuleSearchResult> _results = {};
  final Map<String, KazumiRule> _rules = {};
  final Set<String> _expandedRules = {};
  final Set<String> _loadingChapters = {};
  final Set<String> _captchaRulesInProgress = {};

  List<KazumiRuleCatalogEntry> _catalog = const [];
  String? _loadError;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSources());
  }

  Future<void> _loadSources() async {
    try {
      final installedRules = await widget.resourceService.getInstalledRules();
      if (!mounted) return;
      if (installedRules.isEmpty) {
        setState(() {
          _catalog = const [];
          _loadError = '尚未安装播放规则，请先在设置中打开规则仓库。';
        });
        return;
      }
      final catalog = installedRules
          .map(
            (rule) => KazumiRuleCatalogEntry(
              name: rule.name,
              version: rule.version,
              useNativePlayer: rule.useNativePlayer,
              antiCrawlerEnabled: rule.antiCrawler.enabled,
            ),
          )
          .toList(growable: false);
      setState(() {
        _catalog = catalog;
        for (var index = 0; index < catalog.length; index++) {
          final entry = catalog[index];
          _rules[entry.name] = installedRules[index];
          _results[entry.name] = VideoRuleSearchResult(
            ruleName: entry.name,
            status: VideoRuleSearchStatus.pending,
          );
        }
        _loadError = null;
      });
      for (final rule in installedRules) {
        unawaited(_searchSource(rule));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = '规则列表获取失败：$error');
    }
  }

  Future<void> _searchSource(KazumiRule rule) async {
    try {
      if (rule.deprecated || rule.requiresNewerClient) {
        _setResult(
          rule.name,
          VideoRuleSearchResult(
            ruleName: rule.name,
            status: VideoRuleSearchStatus.unsupported,
            message: rule.deprecated
                ? '规则已被仓库标记为废弃'
                : '规则需要 API Level ${rule.apiVersion}，当前支持到 Level ${KazumiRule.supportedApiLevel}',
          ),
          rule: rule,
        );
        return;
      }
      final keywords = <String>[widget.item.title, ...widget.item.aliases];
      final items = await widget.resourceService.searchRuleWithAliases(
        rule,
        keywords,
      );
      _setResult(
        rule.name,
        VideoRuleSearchResult(
          ruleName: rule.name,
          status: items.isEmpty
              ? VideoRuleSearchStatus.noResult
              : VideoRuleSearchStatus.success,
          items: _rankItems(items),
        ),
        rule: rule,
      );
    } on KazumiCaptchaRequiredException catch (error) {
      if (!mounted) return;
      if (_captchaRulesInProgress.contains(rule.name)) return;
      _captchaRulesInProgress.add(rule.name);
      try {
        final cookieHeader = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (context) => KazumiCaptchaDialog(rule: rule, url: error.url),
        );
        if (!mounted) return;
        if (cookieHeader == null) {
          _setResult(
            rule.name,
            VideoRuleSearchResult(
              ruleName: rule.name,
              status: VideoRuleSearchStatus.error,
              message: '网页验证已取消',
            ),
          );
          return;
        }
        widget.resourceService.setRuleCookieHeader(rule.name, cookieHeader);
        _captchaRulesInProgress.remove(rule.name);
        await _searchSource(rule);
      } finally {
        _captchaRulesInProgress.remove(rule.name);
      }
    } on FormatException catch (error) {
      _setResult(
        rule.name,
        VideoRuleSearchResult(
          ruleName: rule.name,
          status: VideoRuleSearchStatus.unsupported,
          message: error.message,
        ),
      );
    } catch (error) {
      _setResult(
        rule.name,
        VideoRuleSearchResult(
          ruleName: rule.name,
          status: VideoRuleSearchStatus.error,
          message: error.toString(),
        ),
      );
    }
  }

  List<VideoSearchItem> _rankItems(List<VideoSearchItem> items) {
    final keywords = [
      widget.item.title,
      ...widget.item.aliases,
    ].map(_normalize).where((item) => item.isNotEmpty).toSet();
    final ranked = List<VideoSearchItem>.of(items);
    ranked.sort((left, right) {
      final leftScore = _matchScore(left.name, keywords);
      final rightScore = _matchScore(right.name, keywords);
      return rightScore.compareTo(leftScore);
    });
    return ranked;
  }

  int _matchScore(String value, Set<String> keywords) {
    final normalized = _normalize(value);
    if (keywords.contains(normalized)) return 3;
    if (keywords.any(normalized.contains)) return 2;
    if (keywords.any((keyword) => keyword.contains(normalized))) return 1;
    return 0;
  }

  String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\s+|[：:·・,，.。!！?？]'), '');

  void _setResult(
    String name,
    VideoRuleSearchResult result, {
    KazumiRule? rule,
  }) {
    if (!mounted) return;
    setState(() {
      _results[name] = result.copyWith(message: result.message);
      if (rule != null) _rules[name] = rule;
    });
  }

  Future<void> _openSearchItem(KazumiRule rule, VideoSearchItem item) async {
    final key = '${rule.name}:${item.source}';
    if (_loadingChapters.contains(key)) return;
    setState(() => _loadingChapters.add(key));
    try {
      final chapters = await widget.resourceService.getChapters(rule, item);
      final episode = _firstEpisode(chapters);
      if (episode == null) {
        throw const FormatException('该搜索结果没有可用分集');
      }
      _selectEpisode(rule, item, chapters, episode);
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingChapters.remove(key));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('进入播放页失败：$error')));
    }
  }

  VideoEpisode? _firstEpisode(VideoChapterResult chapters) {
    for (final source in chapters.sources) {
      if (source.episodes.isNotEmpty) return source.episodes.first;
    }
    return null;
  }

  void _selectEpisode(
    KazumiRule rule,
    VideoSearchItem item,
    VideoChapterResult chapters,
    VideoEpisode episode,
  ) {
    Navigator.of(context).pop(
      VideoPlaybackSelection(
        rule: rule,
        searchItem: item,
        chapters: chapters,
        episode: episode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: const Color(0xFF10140F),
      insetPadding: const EdgeInsets.symmetric(horizontal: 80, vertical: 42),
      child: SizedBox(
        width: 760,
        height: 620,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '选择播放源',
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '「${widget.item.title}」 · ${_resultCount()} 条结果',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FocusableWidget(
                    onTap: () => Navigator.of(context).pop(),
                    builder: (context, focused) => AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: focused
                            ? theme.colorScheme.primary
                            : Colors.white.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close,
                        color: focused ? Colors.black : Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFF252B25)),
            Expanded(
              child: _loadError != null
                  ? Center(child: Text(_loadError!))
                  : _catalog.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                      itemCount: _catalog.length,
                      itemBuilder: (context, index) {
                        final entry = _catalog[index];
                        return _buildRuleCard(entry);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  int _resultCount() => _results.values.fold<int>(
    0,
    (total, result) => total + result.items.length,
  );

  Widget _buildRuleCard(KazumiRuleCatalogEntry entry) {
    final result = _results[entry.name];
    final expanded = _expandedRules.contains(entry.name);
    final rule = _rules[entry.name];
    final children = <Widget>[];
    if (expanded && result?.status == VideoRuleSearchStatus.success) {
      for (final item in result!.items) {
        children.add(_buildSearchItem(entry.name, rule!, item));
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          FocusableWidget(
            autofocus: entry == _catalog.first,
            onTap: () {
              if (result?.status != VideoRuleSearchStatus.success) return;
              setState(() {
                if (expanded) {
                  _expandedRules.remove(entry.name);
                } else {
                  _expandedRules.add(entry.name);
                }
              });
            },
            builder: (context, focused) =>
                _buildRuleHeader(entry, result, focused),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildRuleHeader(
    KazumiRuleCatalogEntry entry,
    VideoRuleSearchResult? result,
    bool focused,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final status = result?.status ?? VideoRuleSearchStatus.pending;
    final text = switch (status) {
      VideoRuleSearchStatus.pending => '检索中',
      VideoRuleSearchStatus.success => '${result!.items.length} 条',
      VideoRuleSearchStatus.noResult => '无结果',
      VideoRuleSearchStatus.error => '检索失败',
      VideoRuleSearchStatus.unsupported => '暂不支持',
    };
    final statusColor = status == VideoRuleSearchStatus.error
        ? colorScheme.error
        : Colors.white.withValues(alpha: 0.68);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 130),
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: focused
            ? colorScheme.primary
            : Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              entry.name,
              style: TextStyle(
                color: focused ? Colors.black : Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            text,
            style: TextStyle(
              color: focused ? Colors.black : statusColor,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 9),
          if (status == VideoRuleSearchStatus.pending)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: focused ? Colors.black : Colors.white70,
              ),
            )
          else
            Icon(
              Icons.expand_more,
              color: focused ? Colors.black : Colors.white70,
              size: 20,
            ),
        ],
      ),
    );
  }

  Widget _buildSearchItem(
    String ruleName,
    KazumiRule rule,
    VideoSearchItem item,
  ) {
    final key = '$ruleName:${item.source}';
    final loading = _loadingChapters.contains(key);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: FocusableWidget(
        onTap: () => unawaited(_openSearchItem(rule, item)),
        builder: (context, focused) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          constraints: const BoxConstraints(minHeight: 50),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: focused
                ? Colors.white
                : Colors.white.withValues(alpha: 0.035),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: focused ? Colors.black : Colors.white,
                  ),
                ),
              ),
              if (loading)
                SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: focused ? Colors.black : Colors.white70,
                  ),
                )
              else
                Text(
                  '进入播放页',
                  style: TextStyle(
                    color: focused
                        ? Colors.black54
                        : Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              const SizedBox(width: 8),
              Icon(
                Icons.play_arrow_rounded,
                size: 20,
                color: focused ? Colors.black : Colors.white70,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
