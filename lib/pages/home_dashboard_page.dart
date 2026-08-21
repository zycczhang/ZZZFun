import 'package:flutter/material.dart';

import '../anime_nav_widgets.dart';
import '../models/anime_models.dart';
import '../widgets/anime_preview_card.dart';
import '../widgets/app_ui.dart';
import '../widgets/hero_banner.dart';

class HomeDashboard extends StatefulWidget {
  final List<AnimeItem> popularItems;
  final bool popularLoading;
  final String? popularError;
  final VoidCallback onOpenSchedule;
  final ValueChanged<AnimeItem> onOpen;

  const HomeDashboard({
    super.key,
    required this.popularItems,
    required this.popularLoading,
    required this.popularError,
    required this.onOpenSchedule,
    required this.onOpen,
  });

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  int _featuredIndex = 0;

  @override
  void didUpdateWidget(covariant HomeDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.popularItems.isEmpty ||
        _featuredIndex >= widget.popularItems.take(8).length) {
      _featuredIndex = 0;
    }
  }

  void _moveFeatured(int delta) {
    final featuredCount = widget.popularItems.take(8).length;
    if (featuredCount < 2) return;
    setState(() {
      _featuredIndex = (_featuredIndex + delta + featuredCount) % featuredCount;
    });
  }

  @override
  Widget build(BuildContext context) {
    final carouselItems = widget.popularItems.take(8).toList(growable: false);
    final carouselIndex = carouselItems.isEmpty
        ? 0
        : _featuredIndex.clamp(0, carouselItems.length - 1).toInt();
    final featured = carouselItems.isEmpty
        ? null
        : carouselItems[carouselIndex];

    return AppPage(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 18, 38, 42),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (featured != null)
              HeroBanner(
                items: carouselItems,
                selectedIndex: carouselIndex,
                onIndexChanged: (index) =>
                    setState(() => _featuredIndex = index),
                onPrevious: () => _moveFeatured(-1),
                onNext: () => _moveFeatured(1),
                onOpen: () => widget.onOpen(featured),
              )
            else
              DataStatePanel(
                loading: widget.popularLoading,
                title: widget.popularLoading ? '正在获取热门番剧' : '热门番剧获取失败',
                message: widget.popularLoading
                    ? '正在连接 Bangumi 元数据接口，请稍候。'
                    : '接口没有返回可展示的内容，请检查当前网络连接和设置页日志。',
                icon: widget.popularLoading
                    ? Icons.sync_rounded
                    : Icons.cloud_off_outlined,
              ),
            const SizedBox(height: 10),
            SectionHeading(
              title: '热门番剧',
              caption: widget.popularItems.isEmpty
                  ? '暂无数据'
                  : '${widget.popularItems.length} 部',
            ),
            const SizedBox(height: 10),
            if (widget.popularItems.isEmpty)
              const SizedBox(
                height: 180,
                child: Center(
                  child: Text(
                    '热门番剧获取失败',
                    style: TextStyle(color: Colors.white54),
                  ),
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
                    itemCount: widget.popularItems.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      childAspectRatio: 0.55,
                      crossAxisSpacing: 22,
                      mainAxisSpacing: 26,
                    ),
                    itemBuilder: (context, index) {
                      final item = widget.popularItems[index];
                      return PreviewCard(
                        item: item,
                        onTap: () => widget.onOpen(item),
                      );
                    },
                  );
                },
              ),
            if (widget.popularError != null) ...[
              const SizedBox(height: 18),
              const InlineNotice(
                icon: Icons.info_outline_rounded,
                message: '热门番剧接口没有返回数据，未使用本地预览替代。可在设置页查看详细日志。',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
