import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../anime_nav_widgets.dart';
import '../services/app_logger.dart';
import '../services/video_resource_service.dart';
import 'kazumi_rule_repository_page.dart';

enum _SettingsCategory { rules, appearance, developer, storage, about }

class SettingsPage extends StatefulWidget {
  final VideoResourceService resourceService;

  const SettingsPage({super.key, required this.resourceService});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _developerModeKey = 'zzzfun_developer_mode';
  static const _projectUrl = 'https://github.com/zycczhang/ZZZFun';
  static const _rulesUrl = 'https://github.com/Predidit/KazumiRules';

  _SettingsCategory _category = _SettingsCategory.rules;
  bool _developerMode = false;
  bool _developerModeLoaded = false;
  int _imageCacheBytes = 0;

  @override
  void initState() {
    super.initState();
    _imageCacheBytes = PaintingBinding.instance.imageCache.currentSizeBytes;
    unawaited(_loadDeveloperMode());
  }

  Future<void> _loadDeveloperMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _developerMode = prefs.getBool(_developerModeKey) ?? false;
        _developerModeLoaded = true;
      });
    } catch (error, stackTrace) {
      AppLogger.warning('settings', '读取开发者模式失败', error, stackTrace);
      if (mounted) setState(() => _developerModeLoaded = true);
    }
  }

  Future<void> _setDeveloperMode(bool value) async {
    setState(() => _developerMode = value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_developerModeKey, value);
    } catch (error, stackTrace) {
      AppLogger.warning('settings', '保存开发者模式失败', error, stackTrace);
    }
  }

  Future<void> _clearImageCache() async {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    if (!mounted) return;
    setState(
      () => _imageCacheBytes =
          PaintingBinding.instance.imageCache.currentSizeBytes,
    );
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('图片缓存已清除')));
  }

  Future<void> _copyLink(String name, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$name地址已复制')));
  }

  void _showLicense() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF171B18),
        title: const Text('开源许可证'),
        content: const SingleChildScrollView(
          child: Text(
            'ZZZFun 是开源 Flutter 项目。\n\n'
            '项目使用 KazumiRules 提供的规则文件，规则仓库遵循 MIT License。\n\n'
            '第三方声明已随项目源码发布。',
            style: TextStyle(color: Colors.white70, height: 1.55),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080A08),
      body: SafeArea(
        child: Row(
          children: [
            SizedBox(width: 232, child: _buildCategoryRail()),
            Container(width: 1, color: Colors.white.withValues(alpha: 0.06)),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryRail() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(32, 22, 16, 26),
          child: Text(
            '设置',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 14, 22),
            children: [
              _buildCategoryGroup('资源', [
                _SettingsNavEntry(
                  category: _SettingsCategory.rules,
                  icon: Icons.extension_rounded,
                  label: '规则管理',
                ),
              ]),
              const SizedBox(height: 20),
              _buildCategoryGroup('应用', [
                _SettingsNavEntry(
                  category: _SettingsCategory.appearance,
                  icon: Icons.palette_outlined,
                  label: '外观设置',
                ),
                _SettingsNavEntry(
                  category: _SettingsCategory.developer,
                  icon: Icons.code_rounded,
                  label: '开发者模式',
                ),
              ]),
              const SizedBox(height: 20),
              _buildCategoryGroup('其他', [
                _SettingsNavEntry(
                  category: _SettingsCategory.storage,
                  icon: Icons.cleaning_services_outlined,
                  label: '缓存与日志',
                ),
                _SettingsNavEntry(
                  category: _SettingsCategory.about,
                  icon: Icons.info_outline_rounded,
                  label: '关于',
                ),
              ]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryGroup(String title, List<_SettingsNavEntry> entries) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 7),
          child: Text(
            title,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        for (final entry in entries) _buildCategoryItem(entry),
      ],
    );
  }

  Widget _buildCategoryItem(_SettingsNavEntry entry) {
    final selected = entry.category == _category;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: FocusableWidget(
        autofocus: entry.category == _SettingsCategory.rules,
        onTap: () => setState(() => _category = entry.category),
        builder: (context, focused) => AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: focused
                ? Theme.of(context).colorScheme.primary
                : selected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.22)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              Icon(
                entry.icon,
                size: 21,
                color: focused
                    ? Colors.black
                    : selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white70,
              ),
              const SizedBox(width: 13),
              Text(
                entry.label,
                style: TextStyle(
                  color: focused ? Colors.black : Colors.white,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return SizedBox.expand(
      child: switch (_category) {
        _SettingsCategory.rules => KazumiRuleRepositoryPage(
          resourceService: widget.resourceService,
        ),
        _SettingsCategory.appearance => _buildAppearancePage(),
        _SettingsCategory.developer => _buildDeveloperPage(),
        _SettingsCategory.storage => _buildStoragePage(),
        _SettingsCategory.about => _buildAboutPage(),
      },
    );
  }

  Widget _buildAppearancePage() {
    return _SettingsPanel(
      title: '外观设置',
      children: [
        const _SettingsGroupTitle(title: '外观'),
        _SettingsRow(
          icon: Icons.dark_mode_outlined,
          title: '深色模式',
          subtitle: '适合电视和投影仪观看',
          trailing: const Text('深色'),
        ),
        _SettingsRow(
          icon: Icons.palette_outlined,
          title: '配色方案',
          subtitle: '当前界面使用琥珀橙作为强调色',
          trailing: const Text('琥珀橙'),
        ),
        _SettingsRow(
          icon: Icons.text_fields_rounded,
          title: '字体',
          subtitle: '当前使用应用内置字体',
          trailing: const Text('默认'),
        ),
      ],
    );
  }

  Widget _buildDeveloperPage() {
    return _SettingsPanel(
      title: '开发者模式',
      children: [
        const _SettingsGroupTitle(title: '调试'),
        _SettingsRow(
          icon: Icons.code_rounded,
          title: '开发者模式',
          subtitle: '显示网络、播放和应用运行日志',
          trailing: Switch(
            value: _developerMode,
            onChanged: _developerModeLoaded
                ? (value) => unawaited(_setDeveloperMode(value))
                : null,
          ),
          onTap: _developerModeLoaded
              ? () => unawaited(_setDeveloperMode(!_developerMode))
              : null,
        ),
        if (_developerModeLoaded && _developerMode) ...[
          const SizedBox(height: 24),
          _buildLogSection(),
        ],
      ],
    );
  }

  Widget _buildStoragePage() {
    return _SettingsPanel(
      title: '缓存与日志',
      children: [
        const _SettingsGroupTitle(title: '存储'),
        _SettingsRow(
          icon: Icons.cleaning_services_outlined,
          title: '清除图片缓存',
          subtitle: '清除内存中的网络图片缓存，不会删除收藏和观看历史',
          trailing: Text(_formatBytes(_imageCacheBytes)),
          onTap: () => unawaited(_clearImageCache()),
        ),
        const SizedBox(height: 22),
        const _SettingsGroupTitle(title: '日志'),
        _SettingsRow(
          icon: Icons.article_outlined,
          title: '运行日志',
          subtitle: _developerMode ? '开发者模式已开启' : '请先在开发者模式中开启日志',
          trailing: Text('${AppLogger.entries.value.length} 条'),
          onTap: () => setState(() => _category = _SettingsCategory.developer),
        ),
        if (_developerMode) ...[
          const SizedBox(height: 8),
          _SettingsRow(
            icon: Icons.delete_sweep_outlined,
            title: '清空运行日志',
            subtitle: '删除本地保存的日志记录',
            onTap: AppLogger.clear,
          ),
        ],
      ],
    );
  }

  Widget _buildAboutPage() {
    return _SettingsPanel(
      title: '关于',
      children: [
        const _SettingsGroupTitle(title: '项目'),
        _SettingsRow(
          icon: Icons.info_outline_rounded,
          title: 'ZZZFun',
          subtitle: '开源动漫影视盒子',
          trailing: const Text('v1.0.0'),
        ),
        _SettingsRow(
          icon: Icons.home_outlined,
          title: '项目主页',
          subtitle: _projectUrl,
          trailing: const Text('复制地址'),
          onTap: () => unawaited(_copyLink('项目主页', _projectUrl)),
        ),
        _SettingsRow(
          icon: Icons.code_rounded,
          title: '代码仓库',
          subtitle: _projectUrl,
          trailing: const Text('GitHub'),
          onTap: () => unawaited(_copyLink('代码仓库', _projectUrl)),
        ),
        const SizedBox(height: 22),
        const _SettingsGroupTitle(title: '第三方项目'),
        _SettingsRow(
          icon: Icons.extension_outlined,
          title: 'KazumiRules',
          subtitle: '播放规则仓库',
          trailing: const Text('复制地址'),
          onTap: () => unawaited(_copyLink('KazumiRules', _rulesUrl)),
        ),
        _SettingsRow(
          icon: Icons.menu_book_outlined,
          title: 'Bangumi',
          subtitle: '番剧元数据来源',
          trailing: const Text('bgm.tv'),
          onTap: () => unawaited(_copyLink('Bangumi', 'https://bgm.tv')),
        ),
        const SizedBox(height: 22),
        const _SettingsGroupTitle(title: '版本'),
        _SettingsRow(
          icon: Icons.system_update_outlined,
          title: '检查应用更新',
          subtitle: '版本检查功能将在后续接入',
          trailing: const Text('暂未接入'),
        ),
        _SettingsRow(
          icon: Icons.gavel_outlined,
          title: '开源许可证',
          subtitle: '查看 ZZZFun 和第三方项目的许可信息',
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: _showLicense,
        ),
      ],
    );
  }

  Widget _buildLogSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _SettingsGroupTitle(title: '运行日志'),
            const Spacer(),
            ValueListenableBuilder<List<LogEntry>>(
              valueListenable: AppLogger.entries,
              builder: (context, entries, _) => Text(
                '${entries.length} 条',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 300,
          child: ValueListenableBuilder<List<LogEntry>>(
            valueListenable: AppLogger.entries,
            builder: (context, entries, _) {
              if (entries.isEmpty) {
                return const _SettingsEmpty(message: '还没有运行日志');
              }
              return Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF111411),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.07),
                  ),
                ),
                child: ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => Divider(
                    color: Colors.white.withValues(alpha: 0.05),
                    height: 13,
                  ),
                  itemBuilder: (context, index) {
                    final entry = entries[entries.length - index - 1];
                    return Text(
                      entry.line,
                      style: TextStyle(
                        color: _logColor(entry.level),
                        fontFamily: 'Consolas',
                        fontSize: 12,
                        height: 1.35,
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        _SettingsRow(
          icon: Icons.delete_sweep_outlined,
          title: '清空运行日志',
          subtitle: '删除本地保存的日志记录',
          onTap: AppLogger.clear,
        ),
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Color _logColor(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return Colors.white54;
      case LogLevel.info:
        return const Color(0xFFB9C7D8);
      case LogLevel.warning:
        return const Color(0xFFFFC267);
      case LogLevel.error:
        return const Color(0xFFFF8787);
    }
  }
}

class _SettingsNavEntry {
  final _SettingsCategory category;
  final IconData icon;
  final String label;

  const _SettingsNavEntry({
    required this.category,
    required this.icon,
    required this.label,
  });
}

class _SettingsPanel extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsPanel({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: double.infinity,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(34, 22, 40, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 22),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsGroupTitle extends StatelessWidget {
  final String title;

  const _SettingsGroupTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget buildContent(BuildContext context, bool focused) {
      final primaryText = focused ? Colors.black : Colors.white;
      final secondaryText = focused ? Colors.black54 : Colors.white54;
      final iconColor = focused ? Colors.black : Colors.white70;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 21, color: iconColor),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: primaryText,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: secondaryText, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              DefaultTextStyle(
                style: TextStyle(color: secondaryText, fontSize: 12),
                child: IconTheme(
                  data: IconThemeData(color: iconColor),
                  child: trailing!,
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (onTap == null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 4),
        decoration: const BoxDecoration(color: Color(0xFF171B18)),
        child: buildContent(context, false),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: FocusableWidget(
        onTap: onTap,
        builder: (context, focused) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: focused
                ? Theme.of(context).colorScheme.primary
                : const Color(0xFF171B18),
            borderRadius: BorderRadius.circular(10),
          ),
          child: buildContent(context, focused),
        ),
      ),
    );
  }
}

class _SettingsEmpty extends StatelessWidget {
  final String message;

  const _SettingsEmpty({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF171B18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(message, style: const TextStyle(color: Colors.white54)),
    );
  }
}
