import 'package:flutter/material.dart';

import '../anime_nav_widgets.dart';
import '../models/anime_models.dart';
import '../models/bangumi_models.dart';
import '../widgets/anime_preview_card.dart';
import '../widgets/app_ui.dart';

class SchedulePage extends StatelessWidget {
  final List<BangumiCalendarDay> calendarDays;
  final bool calendarLoading;
  final String? calendarError;
  final int selectedWeekday;
  final ValueChanged<int> onWeekdayChanged;
  final Future<void> Function(AnimeItem item) onToggleFavorite;
  final ValueChanged<AnimeItem> onOpen;
  final bool Function(AnimeItem item) isFavorite;

  const SchedulePage({
    super.key,
    required this.calendarDays,
    required this.calendarLoading,
    required this.calendarError,
    required this.selectedWeekday,
    required this.onWeekdayChanged,
    required this.onToggleFavorite,
    required this.onOpen,
    required this.isFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final selectedDay = _findDay(selectedWeekday);
    final items =
        selectedDay?.subjects
            .map(AnimeItem.fromBangumi)
            .toList(growable: false) ??
        const <AnimeItem>[];

    return AppPage(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 24, 38, 42),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _WeekdaySelector(
              days: calendarDays,
              selectedWeekday: selectedWeekday,
              onChanged: onWeekdayChanged,
            ),
            if (calendarError != null) ...[
              const SizedBox(height: 16),
              const InlineNotice(
                icon: Icons.cloud_off_outlined,
                message: '放送日历获取失败，当前没有可展示的更新数据。请检查网络或前往设置查看日志。',
              ),
            ],
            const SizedBox(height: 16),
            SectionHeading(
              title: selectedDay?.weekdayCn ?? weekdayLabel(selectedWeekday),
              caption: items.isEmpty ? '暂无数据' : '${items.length} 部更新',
            ),
            const SizedBox(height: 18),
            if (calendarLoading && calendarDays.isEmpty)
              const SizedBox(
                height: 260,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (items.isEmpty)
              const SizedBox(
                height: 260,
                child: EmptyState(
                  icon: Icons.event_busy_outlined,
                  title: '当天没有可展示的番剧',
                  message: '接口没有返回该日期的放送内容。',
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 760
                      ? 5
                      : constraints.maxWidth >= 600
                      ? 4
                      : constraints.maxWidth >= 560
                      ? 3
                      : 2;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: items.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      childAspectRatio: 0.55,
                      crossAxisSpacing: 22,
                      mainAxisSpacing: 26,
                    ),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return PreviewCard(
                        item: item,
                        isFavorite: isFavorite(item),
                        onTap: () => onOpen(item),
                        onFavorite: () => onToggleFavorite(item),
                      );
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  BangumiCalendarDay? _findDay(int weekday) {
    for (final day in calendarDays) {
      if (day.weekdayId == weekday) return day;
    }
    return null;
  }
}

class _WeekdaySelector extends StatelessWidget {
  final List<BangumiCalendarDay> days;
  final int selectedWeekday;
  final ValueChanged<int> onChanged;

  const _WeekdaySelector({
    required this.days,
    required this.selectedWeekday,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 7,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final weekday = index + 1;
          final day = _dayFor(weekday);
          final selected = weekday == selectedWeekday;
          return SizedBox(
            width: 68,
            child: FocusableWidget(
              onTap: () => onChanged(weekday),
              builder: (context, focused) {
                final primary = Theme.of(context).colorScheme.primary;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: focused
                        ? primary
                        : selected
                        ? primary.withOpacity(0.16)
                        : const Color(0xFF171A20),
                    borderRadius: BorderRadius.circular(9),
                    border: selected && !focused
                        ? Border.all(color: primary.withOpacity(0.5))
                        : null,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          weekdayLabel(weekday),
                          style: TextStyle(
                            color: focused
                                ? Colors.black
                                : selected
                                ? Colors.white
                                : Colors.white70,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          day == null ? '暂无数据' : '${day.subjects.length} 部',
                          style: TextStyle(
                            color: focused
                                ? Colors.black54
                                : selected
                                ? Colors.white54
                                : Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  BangumiCalendarDay? _dayFor(int weekday) {
    for (final day in days) {
      if (day.weekdayId == weekday) return day;
    }
    return null;
  }
}
