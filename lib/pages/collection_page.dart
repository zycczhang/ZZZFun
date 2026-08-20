import 'package:flutter/material.dart';

import '../anime_nav_widgets.dart';
import '../models/anime_models.dart';
import '../widgets/anime_preview_card.dart';
import '../widgets/app_ui.dart';

class CollectionPage extends StatelessWidget {
  final List<AnimeItem> favorites;
  final List<AnimeItem> history;
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
                      items: history,
                      emptyIcon: Icons.history_rounded,
                      emptyTitle: '还没有观看记录',
                      emptyMessage: '打开番剧详情后，最近浏览的内容会显示在这里。',
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
  final ValueChanged<AnimeItem> onOpen;
  final Future<void> Function(AnimeItem item)? onFavorite;

  const _LibraryGrid({
    required this.items,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyMessage,
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
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        childAspectRatio: 0.55,
        crossAxisSpacing: 16,
        mainAxisSpacing: 24,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return PreviewCard(
          item: item,
          isFavorite: isFavorite,
          onTap: () => onOpen(item),
          onFavorite: onFavorite == null ? null : () => onFavorite!(item),
        );
      },
    );
  }
}
