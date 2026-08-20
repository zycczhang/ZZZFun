import 'package:flutter/material.dart';

import '../models/anime_models.dart';
import '../services/app_logger.dart';

class AppPage extends StatelessWidget {
  final Widget child;

  const AppPage({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: const Color(0xFF0E1014), child: child);
  }
}

class PageHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget? trailing;

  const PageHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 29,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 14), trailing!],
      ],
    );
  }
}

class ItemMeta extends StatelessWidget {
  final AnimeItem item;
  final bool compact;

  const ItemMeta({super.key, required this.item, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (item.score != null && item.score! > 0)
        '★ ${item.score!.toStringAsFixed(1)}',
      if (item.airDate != null && item.airDate!.isNotEmpty)
        item.airDate!.split('-').first,
      if (item.episodeCount != null && item.episodeCount! > 0)
        '${item.episodeCount} 集',
    ];
    if (parts.isEmpty) parts.add(item.category);
    return Text(
      parts.join('  ·  '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: item.score != null && item.score! > 0
            ? Theme.of(context).colorScheme.primary
            : Colors.white54,
        fontSize: compact ? 11 : 13,
        fontWeight: compact ? FontWeight.w400 : FontWeight.w600,
      ),
    );
  }
}

class StatusTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;

  const StatusTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF15181E),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class DataStatePanel extends StatelessWidget {
  final bool loading;
  final String title;
  final String message;
  final IconData icon;

  const DataStatePanel({
    super.key,
    required this.loading,
    required this.title,
    required this.message,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      height: 300,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF15181E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: loading ? primary : Colors.white38),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 7),
            Text(
              message,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class InlineNotice extends StatelessWidget {
  final IconData icon;
  final String message;

  const InlineNotice({super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF15181E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white54),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color logColor(LogLevel level) {
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

String weekdayLabel(int weekday) {
  const names = ['一', '二', '三', '四', '五', '六', '日'];
  if (weekday < 1 || weekday > 7) return '日期';
  return '周${names[weekday - 1]}';
}
