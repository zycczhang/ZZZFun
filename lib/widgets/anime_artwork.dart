import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/anime_models.dart';

class PosterArt extends StatelessWidget {
  final AnimeItem item;
  final bool focused;

  const PosterArt({super.key, required this.item, this.focused = false});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF171A20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: focused ? primary : Colors.white.withOpacity(0.08),
          width: focused ? 2 : 1,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PosterBackdrop(item: item, cacheWidth: 480),
          if (item.posterUrl != null && item.posterUrl!.isNotEmpty)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.5)],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class PosterBackdrop extends StatelessWidget {
  final AnimeItem item;
  final int? cacheWidth;

  const PosterBackdrop({super.key, required this.item, this.cacheWidth});

  @override
  Widget build(BuildContext context) {
    final url = item.posterUrl;
    if (url != null && url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        memCacheWidth: cacheWidth,
        maxWidthDiskCache: cacheWidth,
        maxHeightDiskCache: cacheWidth == null ? null : cacheWidth! * 3 ~/ 2,
        filterQuality: FilterQuality.low,
        fadeInDuration: Duration.zero,
        placeholder: (context, url) => _ArtworkFallback(item: item),
        errorWidget: (context, url, error) => _ArtworkFallback(item: item),
      );
    }
    return _ArtworkFallback(item: item);
  }
}

class _ArtworkFallback extends StatelessWidget {
  final AnimeItem item;

  const _ArtworkFallback({required this.item});

  static const palettes = [
    [Color(0xFF182D47), Color(0xFF9E3D4B)],
    [Color(0xFF174C57), Color(0xFFC87829)],
    [Color(0xFF242858), Color(0xFF8652A0)],
    [Color(0xFF54313E), Color(0xFFAF773D)],
    [Color(0xFF16434A), Color(0xFF4A9975)],
    [Color(0xFF30345D), Color(0xFFB65378)],
  ];

  @override
  Widget build(BuildContext context) {
    final colors = palettes[item.colorSeed.abs() % palettes.length];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            right: -24,
            top: 24,
            child: Icon(
              _posterIcon(item.colorSeed),
              size: 124,
              color: Colors.white.withOpacity(0.1),
            ),
          ),
        ],
      ),
    );
  }

  IconData _posterIcon(int seed) {
    const icons = [
      Icons.nights_stay_rounded,
      Icons.waves_rounded,
      Icons.public_rounded,
      Icons.movie_filter_rounded,
      Icons.wb_twilight_rounded,
      Icons.terrain_rounded,
    ];
    return icons[seed.abs() % icons.length];
  }
}
