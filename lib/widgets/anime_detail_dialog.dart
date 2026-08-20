import 'package:flutter/material.dart';

import '../models/anime_models.dart';
import 'anime_artwork.dart';
import 'app_ui.dart';

class PreviewDialog extends StatelessWidget {
  final AnimeItem item;
  final bool isFavorite;
  final VoidCallback? onFavorite;

  const PreviewDialog({
    super.key,
    required this.item,
    required this.isFavorite,
    this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF191C22),
      insetPadding: const EdgeInsets.all(18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 570;
          final details = _details(context);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 230,
                        width: 164,
                        child: PosterArt(item: item),
                      ),
                      const SizedBox(height: 20),
                      details,
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 246,
                        width: 174,
                        child: PosterArt(item: item),
                      ),
                      const SizedBox(width: 24),
                      Expanded(child: details),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _details(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.title,
          style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        ItemMeta(item: item),
        const SizedBox(height: 18),
        Text(
          item.description,
          style: const TextStyle(color: Colors.white70, height: 1.55),
        ),
        const SizedBox(height: 18),
        if (item.tags.isNotEmpty)
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: item.tags
                .take(6)
                .map(
                  (tag) => Chip(
                    label: Text(tag),
                    labelStyle: const TextStyle(fontSize: 11),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide.none,
                  ),
                )
                .toList(),
          ),
        const SizedBox(height: 20),
        const InlineNotice(
          icon: Icons.info_outline_rounded,
          message: '当前已接入番剧元数据，播放资源和视频链接将在后续内容源确定后接入。',
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
            if (onFavorite != null) ...[
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: onFavorite,
                icon: Icon(
                  isFavorite
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  size: 18,
                ),
                label: Text(isFavorite ? '取消收藏' : '加入收藏'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
