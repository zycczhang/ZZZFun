import 'dart:async';

import 'package:flutter/material.dart';

import '../anime_nav_widgets.dart';
import '../models/kazumi_rule_models.dart';
import '../services/app_logger.dart';
import '../services/video_resource_service.dart';
import '../widgets/app_ui.dart';

class KazumiRuleRepositoryPage extends StatefulWidget {
  final VideoResourceService resourceService;

  const KazumiRuleRepositoryPage({super.key, required this.resourceService});

  @override
  State<KazumiRuleRepositoryPage> createState() =>
      _KazumiRuleRepositoryPageState();
}

class _KazumiRuleRepositoryPageState extends State<KazumiRuleRepositoryPage> {
  List<KazumiRuleCatalogEntry> _catalog = const [];
  Map<String, KazumiRule> _installed = const {};
  final Set<String> _busyRules = {};
  bool _loading = true;
  bool _remoteCheckFailed = false;
  String? _error;

  int get _availableUpdateCount => _catalog.where((entry) {
    final installed = _installed[entry.name];
    return installed != null &&
        entry.version.isNotEmpty &&
        installed.version.isNotEmpty &&
        entry.version != installed.version;
  }).length;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (mounted) setState(() => _loading = true);
    List<KazumiRule> installedRules = const [];
    try {
      installedRules = await widget.resourceService.getInstalledRules();
    } catch (error, stackTrace) {
      AppLogger.warning('kazumi-rules', '读取已安装规则失败', error, stackTrace);
    }
    try {
      List<KazumiRuleCatalogEntry> catalog;
      var remoteCheckFailed = false;
      try {
        catalog = forceRefresh
            ? await widget.resourceService.refreshRuleCatalog()
            : await widget.resourceService.getRuleCatalog();
      } catch (error, stackTrace) {
        AppLogger.warning(
          'kazumi-rules',
          '在线规则索引不可用，使用本地规则',
          error,
          stackTrace,
        );
        remoteCheckFailed = forceRefresh;
        catalog = _catalog;
      }
      final byName = {for (final entry in catalog) entry.name: entry};
      for (final rule in installedRules) {
        byName.putIfAbsent(
          rule.name,
          () => KazumiRuleCatalogEntry(
            name: rule.name,
            version: rule.version,
            useNativePlayer: rule.useNativePlayer,
            antiCrawlerEnabled: rule.antiCrawler.enabled,
          ),
        );
      }
      final merged = byName.values.toList()
        ..sort((left, right) => left.name.compareTo(right.name));
      if (!mounted) return;
      setState(() {
        _catalog = merged;
        _installed = {for (final rule in installedRules) rule.name: rule};
        _loading = false;
        _remoteCheckFailed = remoteCheckFailed;
        _error = catalog.isEmpty && installedRules.isEmpty
            ? '规则仓库加载失败，请检查网络后重试。'
            : null;
      });
    } catch (error, stackTrace) {
      AppLogger.warning('kazumi-rules', '规则仓库加载失败', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _remoteCheckFailed = forceRefresh;
        _error = '规则仓库加载失败，请检查网络后重试。';
      });
    }
  }

  Future<void> _install(
    KazumiRuleCatalogEntry entry, {
    required bool update,
  }) async {
    if (_busyRules.contains(entry.name)) return;
    setState(() => _busyRules.add(entry.name));
    try {
      await widget.resourceService.installRule(
        entry.name,
        forceRefresh: update,
      );
      await _load();
      if (mounted) {
        _showMessage(update ? '规则已更新：${entry.name}' : '规则已安装：${entry.name}');
      }
    } catch (error, stackTrace) {
      AppLogger.warning(
        'kazumi-rules',
        '规则操作失败: ${entry.name}',
        error,
        stackTrace,
      );
      if (mounted) _showMessage('操作失败：${entry.name}');
    } finally {
      if (mounted) setState(() => _busyRules.remove(entry.name));
    }
  }

  Future<void> _uninstall(KazumiRuleCatalogEntry entry) async {
    if (_busyRules.contains(entry.name)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF171B18),
        title: const Text('删除播放规则'),
        content: Text('确定删除“${entry.name}”吗？删除后将无法使用该来源。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyRules.add(entry.name));
    try {
      await widget.resourceService.uninstallRule(entry.name);
      await _load();
      if (mounted) _showMessage('规则已删除：${entry.name}');
    } catch (error, stackTrace) {
      AppLogger.warning(
        'kazumi-rules',
        '删除规则失败: ${entry.name}',
        error,
        stackTrace,
      );
      if (mounted) _showMessage('删除失败：${entry.name}');
    } finally {
      if (mounted) setState(() => _busyRules.remove(entry.name));
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _checkRemoteUpdates() async {
    if (_loading) return;
    await _load(forceRefresh: true);
    if (!mounted) return;
    if (_remoteCheckFailed || _error != null) {
      _showMessage('远程规则仓库检查失败，请稍后重试');
      return;
    }
    final count = _availableUpdateCount;
    _showMessage(count == 0 ? '远程规则仓库已是最新' : '发现 $count 项规则可以更新');
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 38, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 24),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final updateCount = _availableUpdateCount;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '规则仓库',
                style: TextStyle(fontSize: 29, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 5),
              Text(
                updateCount == 0
                    ? '安装后才会参与播放源检索，规则文件保存在本地。'
                    : '发现 $updateCount 项规则可以更新。',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Text(
          '${_installed.length} 个已安装',
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
        const SizedBox(width: 10),
        _HeaderIconButton(
          icon: _loading ? Icons.sync_rounded : Icons.refresh_rounded,
          tooltip: '检查远程规则更新',
          onTap: _loading ? null : () => unawaited(_checkRemoteUpdates()),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading && _catalog.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _catalog.isEmpty) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: '暂时无法获取规则',
        message: _error!,
      );
    }
    if (_catalog.isEmpty) {
      return const EmptyState(
        icon: Icons.extension_outlined,
        title: '暂无规则',
        message: '规则仓库没有返回可用的播放规则。',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: _catalog.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _buildRuleRow(_catalog[index]),
    );
  }

  Widget _buildRuleRow(KazumiRuleCatalogEntry entry) {
    final installed = _installed[entry.name];
    final isInstalled = installed != null;
    final hasUpdate =
        isInstalled &&
        entry.version.isNotEmpty &&
        installed.version.isNotEmpty &&
        entry.version != installed.version;
    final busy = _busyRules.contains(entry.name);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF15191F),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text(
                      isInstalled
                          ? '已安装 ${installed.version}'
                          : '版本 ${entry.version}',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                    if (hasUpdate)
                      Text(
                        '最新 ${entry.version}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 12,
                        ),
                      ),
                    if (entry.lastUpdate != null)
                      Text(
                        '更新于 ${_formatDate(entry.lastUpdate!)}',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    if (entry.antiCrawlerEnabled)
                      const Text(
                        '需要验证',
                        style: TextStyle(
                          color: Color(0xFFFFC267),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 22),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (!isInstalled)
            _RuleActionButton(
              label: '安装',
              icon: Icons.download_rounded,
              onTap: () => unawaited(_install(entry, update: false)),
            )
          else ...[
            if (hasUpdate)
              _RuleActionButton(
                label: '更新',
                icon: Icons.system_update_alt_rounded,
                onTap: () => unawaited(_install(entry, update: true)),
              )
            else
              const _InstalledMark(),
            const SizedBox(width: 8),
            _RuleIconButton(
              icon: Icons.delete_outline_rounded,
              tooltip: '删除规则',
              onTap: () => unawaited(_uninstall(entry)),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(int value) {
    final milliseconds = value < 100000000000 ? value * 1000 : value;
    final date = DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: FocusableWidget(
        enabled: onTap != null,
        onTap: onTap,
        builder: (context, focused) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 42,
          height: 38,
          decoration: BoxDecoration(
            color: focused
                ? Theme.of(context).colorScheme.primary
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(
            icon,
            size: 20,
            color: focused ? Colors.black : Colors.white70,
          ),
        ),
      ),
    );
  }
}

class _RuleActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _RuleActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FocusableWidget(
      onTap: onTap,
      builder: (context, focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        constraints: const BoxConstraints(minWidth: 76, minHeight: 38),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: focused
              ? Theme.of(context).colorScheme.primary
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 17,
              color: focused ? Colors.black : Colors.white70,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: focused ? Colors.black : Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RuleIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _RuleIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: FocusableWidget(
        onTap: onTap,
        builder: (context, focused) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: focused
                ? Theme.of(context).colorScheme.primary
                : Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(
            icon,
            size: 19,
            color: focused ? Colors.black : Colors.white60,
          ),
        ),
      ),
    );
  }
}

class _InstalledMark extends StatelessWidget {
  const _InstalledMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 76, minHeight: 38),
      alignment: Alignment.center,
      child: const Text(
        '已安装',
        style: TextStyle(color: Color(0xFF70DDA7), fontSize: 12),
      ),
    );
  }
}
