import 'package:flutter/material.dart';

import '../anime_nav_widgets.dart';
import '../services/app_logger.dart';
import '../widgets/app_ui.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPage(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 38, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PageHeader(
              eyebrow: 'ZZZFUN / SETTINGS',
              title: '设置与日志',
              subtitle: '查看应用状态、内容源状态和最近运行日志。',
            ),
            const SizedBox(height: 22),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 680;
                final tiles = [
                  const StatusTile(
                    icon: Icons.check_circle_outline,
                    title: '应用状态',
                    value: '运行正常',
                    color: Color(0xFF5ED49A),
                  ),
                  StatusTile(
                    icon: Icons.storage_outlined,
                    title: '数据模式',
                    value: '仅本地',
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const StatusTile(
                    icon: Icons.link_off_rounded,
                    title: '播放资源',
                    value: '未配置',
                    color: Colors.white54,
                  ),
                ];
                return compact
                    ? Column(
                        children: [
                          for (
                            var index = 0;
                            index < tiles.length;
                            index++
                          ) ...[
                            tiles[index],
                            if (index != tiles.length - 1)
                              const SizedBox(height: 10),
                          ],
                        ],
                      )
                    : Row(
                        children: [
                          for (
                            var index = 0;
                            index < tiles.length;
                            index++
                          ) ...[
                            Expanded(child: tiles[index]),
                            if (index != tiles.length - 1)
                              const SizedBox(width: 14),
                          ],
                        ],
                      );
              },
            ),
            const SizedBox(height: 24),
            SectionHeading(
              title: '运行日志',
              caption: '最近 300 条',
              trailing: ValueListenableBuilder<List<LogEntry>>(
                valueListenable: AppLogger.entries,
                builder: (context, entries, _) => Row(
                  children: [
                    Text(
                      '${entries.length} 条',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: entries.isEmpty ? null : AppLogger.clear,
                      tooltip: '清空日志',
                      icon: const Icon(Icons.delete_sweep_outlined),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ValueListenableBuilder<List<LogEntry>>(
                valueListenable: AppLogger.entries,
                builder: (context, entries, _) {
                  if (entries.isEmpty) {
                    return const EmptyState(
                      icon: Icons.article_outlined,
                      title: '还没有日志',
                      message: '应用运行事件会显示在这里。',
                    );
                  }
                  return Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF111318),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(14),
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => Divider(
                        color: Colors.white.withOpacity(0.05),
                        height: 14,
                      ),
                      itemBuilder: (context, index) {
                        final entry = entries[entries.length - index - 1];
                        return Text(
                          entry.line,
                          style: TextStyle(
                            color: logColor(entry.level),
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
          ],
        ),
      ),
    );
  }
}
