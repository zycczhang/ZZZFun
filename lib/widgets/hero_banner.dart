import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../anime_nav_widgets.dart';
import '../models/anime_models.dart';
import 'anime_artwork.dart';
import 'app_ui.dart';

class HeroBanner extends StatelessWidget {
  final List<AnimeItem> items;
  final int selectedIndex;
  final ValueChanged<int> onIndexChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onOpen;

  const HeroBanner({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onIndexChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final item = items[selectedIndex];
    final primary = Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        final imageStart = compact
            ? constraints.maxWidth * 0.16
            : constraints.maxWidth * 0.22;
        return FocusableWidget(
          onTap: onOpen,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              if (selectedIndex == 0) return KeyEventResult.ignored;
              onPrevious();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              if (selectedIndex == items.length - 1) {
                return KeyEventResult.handled;
              }
              onNext();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          builder: (context, focused) => Container(
            height: compact ? 292 : 318,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFF08090C),
              borderRadius: BorderRadius.zero,
              border: focused
                  ? Border.all(color: primary.withOpacity(0.7), width: 2)
                  : null,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  left: imageStart,
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    child: SizedBox.expand(
                      key: ValueKey(item.id),
                      child: PosterBackdrop(item: item, cacheWidth: 1280),
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        const Color(0xFF08090C),
                        const Color(0xFF08090C).withOpacity(0.98),
                        const Color(0xFF08090C).withOpacity(0.72),
                        const Color(0xFF08090C).withOpacity(0.28),
                        Colors.transparent,
                      ],
                      stops: const [0, 0.18, 0.38, 0.62, 0.95],
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        const Color(0xFF08090C).withOpacity(0.72),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: compact ? 22 : 30,
                  right: constraints.maxWidth * (compact ? 0.22 : 0.5),
                  top: compact ? 24 : 34,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 27 : 34,
                          fontWeight: FontWeight.w900,
                          height: 1.08,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ItemMeta(item: item),
                      const SizedBox(height: 12),
                      Text(
                        item.description,
                        maxLines: compact ? 4 : 5,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          height: 1.55,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (items.length > 1)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 14,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var index = 0; index < items.length; index++)
                          GestureDetector(
                            onTap: () => onIndexChanged(index),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: index == selectedIndex ? 20 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: index == selectedIndex
                                    ? primary
                                    : Colors.white54,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
