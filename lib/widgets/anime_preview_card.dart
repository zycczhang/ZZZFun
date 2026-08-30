import 'package:flutter/material.dart';

import '../anime_nav_widgets.dart';
import '../models/anime_models.dart';
import 'anime_artwork.dart';
import 'app_ui.dart';

class PreviewCard extends StatelessWidget {
  final AnimeItem item;
  final bool isFavorite;
  final double? width;
  final FocusNode? focusNode;
  final KeyEventResult Function(FocusNode node, KeyEvent event)? onKeyEvent;
  final String? secondaryText;
  final VoidCallback onTap;
  final VoidCallback? onFavorite;

  const PreviewCard({
    super.key,
    required this.item,
    this.isFavorite = false,
    this.width,
    this.focusNode,
    this.onKeyEvent,
    this.secondaryText,
    required this.onTap,
    this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final card = FocusableWidget(
      focusNode: focusNode,
      onKeyEvent: onKeyEvent,
      onTap: onTap,
      builder: (context, focused) {
        return AnimatedScale(
          scale: focused ? 1.035 : 1,
          duration: const Duration(milliseconds: 150),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 0.67,
                child: PosterArt(item: item, focused: focused),
              ),
              const SizedBox(height: 9),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              ItemMeta(item: item, compact: true),
              if (secondaryText != null) ...[
                const SizedBox(height: 4),
                Text(
                  secondaryText!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                    height: 1.25,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
    return SizedBox(width: width, child: card);
  }
}
