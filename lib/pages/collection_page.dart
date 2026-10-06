import 'package:flutter/material.dart';

import '../anime_nav_widgets.dart';
import '../models/anime_models.dart';
import '../models/watch_history_models.dart';
import '../widgets/anime_preview_card.dart';
import '../widgets/app_ui.dart';

class CollectionPage extends StatelessWidget {
  final List<AnimeItem> favorites;
  final List<WatchHistoryEntry> history;
  final Future<void> Function(AnimeItem item) onToggleFavorite;
  final ValueChanged<AnimeItem> onOpen;

  const CollectionPage({
    super.key,
    required this.favorites,
    required this.history,
    required this.onToggleFavorite,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return AppPage(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 38, 24),
        child: DefaultTabController(
          length: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: '我的收藏  ${favorites.length}'),
                  Tab(text: '观看历史  ${history.length}'),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(
                child: TabBarView(
                  children: [
                    _LibraryGrid(
                      items: favorites,
                      emptyIcon: Icons.bookmark_border_rounded,
                      emptyTitle: '还没有收藏',
                      emptyMessage: '在首页或日期表收藏喜欢的番剧，它们会保存在这里。',
                      isFavorite: true,
                      onOpen: onOpen,
                      onFavorite: onToggleFavorite,
                    ),
                    _LibraryGrid(
                      items: history
                          .map((entry) => entry.item)
                          .toList(growable: false),
                      detailByItemId: {
                        for (final entry in history)
                          entry.item.id: entry.displaySummary,
                      },
                      emptyIcon: Icons.history_rounded,
                      emptyTitle: '还没有观看记录',
                      emptyMessage: '开始播放后，最近观看的内容会显示在这里。',
                      onOpen: onOpen,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryGrid extends StatelessWidget {
  final List<AnimeItem> items;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;
  final bool isFavorite;
  final Map<String, String> detailByItemId;
  final ValueChanged<AnimeItem> onOpen;
  final Future<void> Function(AnimeItem item)? onFavorite;

  const _LibraryGrid({
    required this.items,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyMessage,
    this.detailByItemId = const {},
    required this.onOpen,
    this.isFavorite = false,
    this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return EmptyState(
        icon: emptyIcon,
        title: emptyTitle,
        message: emptyMessage,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = adaptiveAnimeGridColumnCount(
          constraints.maxWidth,
        );
        const spacing = animeGridCrossAxisSpacing;
        const posterAspectRatio = 0.67;
        // Match PreviewCard's poster, title/meta rows, and optional two-line
        // history summary so the grid height follows the computed card width.
        const cardTextTopGap = 9.0;
        const titleLineHeight = 17.0;
        const titleToMetaGap = 4.0;
        const metadataLineHeight = 13.0;
        const historySummaryGap = 4.0;
        const historySummaryHeight = 25.0;
        const focusRoom = 10.0;
        final cardWidth =
            (constraints.maxWidth - spacing * (columnCount - 1)) / columnCount;
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final hasHistoryDetails = detailByItemId.isNotEmpty;
        final cardDetailsHeight =
            (cardTextTopGap +
                titleLineHeight +
                titleToMetaGap +
                metadataLineHeight +
                (hasHistoryDetails
                    ? historySummaryGap + historySummaryHeight
                    : 0) +
                focusRoom) *
            textScale;
        final cardHeight = cardWidth / posterAspectRatio + cardDetailsHeight;

        return GridView.builder(
          padding: const EdgeInsets.only(bottom: 20),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columnCount,
            childAspectRatio: cardWidth / cardHeight,
            crossAxisSpacing: spacing,
            mainAxisSpacing: animeGridMainAxisSpacing,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return PreviewCard(
              item: item,
              isFavorite: isFavorite,
              secondaryText: detailByItemId[item.id],
              onTap: () => onOpen(item),
              onFavorite: onFavorite == null ? null : () => onFavorite!(item),
            );
          },
        );
      },
    );
  }
}
