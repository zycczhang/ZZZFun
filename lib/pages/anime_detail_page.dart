import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/anime_models.dart';
import '../models/video_source_models.dart';
import '../models/watch_history_models.dart';
import '../anime_nav_widgets.dart';
import '../services/video_resource_service.dart';
import '../widgets/anime_artwork.dart';
import '../widgets/app_ui.dart';
import 'video_player_page.dart';
import 'video_source_picker_dialog.dart';

class AnimeDetailPage extends StatelessWidget {
  final AnimeItem item;
  final bool isFavorite;
  final bool loadingDetails;
  final WatchHistoryEntry? historyEntry;
  final VoidCallback onBack;
  final VoidCallback onToggleFavorite;
  final Future<void> Function()? onHistoryChanged;
  final VideoResourceService resourceService;

  const AnimeDetailPage({
    super.key,
    required this.item,
    required this.isFavorite,
    this.loadingDetails = false,
    this.historyEntry,
    required this.onBack,
    required this.onToggleFavorite,
    this.onHistoryChanged,
    required this.resourceService,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) onBack();
      },
      child: Focus(
        onKeyEvent: (node, event) {
          // Android TV's remote Back is also delivered through PopScope.
          // Handling goBack here as well would close the detail and then pop
          // the app's root route for the same physical button press.
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            onBack();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Scaffold(
          backgroundColor: const Color(0xFF080A0D),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 760;
              return Stack(
                fit: StackFit.expand,
                children: [
                  _buildBackdrop(context, constraints),
                  _buildTopShade(),
                  _buildBottomShade(),
                  Positioned.fill(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 24 : 72,
                        compact ? 84 : 92,
                        compact ? 24 : 72,
                        compact ? 34 : 58,
                      ),
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: compact
                                ? constraints.maxWidth
                                : constraints.maxWidth * 0.7,
                          ),
                          child: _buildContent(context, compact),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBackdrop(BuildContext context, BoxConstraints constraints) {
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFF080A0D)),
          Positioned(
            left: constraints.maxWidth < 760
                ? constraints.maxWidth * 0.08
                : constraints.maxWidth * 0.18,
            right: 0,
            top: 0,
            bottom: 0,
            child: PosterBackdrop(
              item: item,
              cacheWidth: (constraints.maxWidth * 1.5).round().clamp(720, 1920),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  const Color(0xFF080A0D),
                  const Color(0xFF080A0D).withValues(alpha: 0.98),
                  const Color(0xFF080A0D).withValues(alpha: 0.78),
                  const Color(0xFF080A0D).withValues(alpha: 0.32),
                  Colors.transparent,
                ],
                stops: const [0, 0.18, 0.4, 0.67, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopShade() {
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.center,
              colors: [
                const Color(0xFF080A0D).withValues(alpha: 0.72),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomShade() {
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.center,
              colors: [
                const Color(0xFF080A0D).withValues(alpha: 0.98),
                const Color(0xFF080A0D).withValues(alpha: 0.82),
                Colors.transparent,
              ],
              stops: const [0, 0.34, 0.8],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, bool compact) {
    final primary = Theme.of(context).colorScheme.primary;
    final titleSize = compact ? 30.0 : 44.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: titleSize,
            fontWeight: FontWeight.w800,
            height: 1.08,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 10)],
          ),
        ),
        if (item.subtitle.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            item.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: compact ? 14 : 17,
            ),
          ),
        ],
        const SizedBox(height: 16),
        ItemMeta(item: item),
        if (loadingDetails) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '正在加载完整资料',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        _buildInfoRow(context, compact),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: compact ? double.infinity : 720,
          ),
          child: Text(
            item.description,
            maxLines: compact ? 7 : 5,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.84),
              fontSize: compact ? 13 : 15,
              height: 1.55,
              shadows: const [Shadow(color: Colors.black87, blurRadius: 6)],
            ),
          ),
        ),
        if (item.tags.isNotEmpty) ...[
          const SizedBox(height: 18),
          _buildTags(context),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            _DetailActionButton(
              icon: Icons.play_arrow_rounded,
              label: historyEntry?.hasPlaybackSelection == true
                  ? '继续播放'
                  : '开始观看',
              focusedColor: primary,
              onTap: () => _openPlayback(context),
            ),
            const SizedBox(width: 12),
            _DetailActionButton(
              icon: isFavorite
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              label: isFavorite ? '已收藏' : '收藏',
              focusedColor: Colors.white,
              onTap: onToggleFavorite,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openPlayback(BuildContext context) async {
    final savedHistory = historyEntry;
    var resumePosition = Duration.zero;
    var selection = savedHistory?.hasPlaybackSelection == true
        ? await _restoreSelection(savedHistory!)
        : null;
    if (selection != null) resumePosition = savedHistory!.position;
    if (!context.mounted) return;
    selection ??= await showDialog<VideoPlaybackSelection>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          VideoSourcePickerDialog(item: item, resourceService: resourceService),
    );
    final playbackSelection = selection;
    if (playbackSelection == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => VideoPlayerPage(
          item: item,
          selection: playbackSelection,
          initialPosition: resumePosition,
          resourceService: resourceService,
        ),
      ),
    );
    if (context.mounted) await onHistoryChanged?.call();
  }

  Future<VideoPlaybackSelection?> _restoreSelection(
    WatchHistoryEntry history,
  ) async {
    try {
      final rule = await resourceService.getInstalledRule(history.sourceSite);
      if (rule == null) return null;
      final searchItem = VideoSearchItem(
        name: history.searchItemName.isEmpty
            ? item.title
            : history.searchItemName,
        source: history.searchItemSource,
        ruleName: rule.name,
      );
      final chapters = await resourceService.getChapters(rule, searchItem);
      if (chapters.sources.isEmpty) return null;

      var sourceIndex = chapters.sources.indexWhere(
        (source) => source.name == history.sourceLine,
      );
      if (sourceIndex < 0 &&
          history.sourceIndex >= 0 &&
          history.sourceIndex < chapters.sources.length) {
        sourceIndex = history.sourceIndex;
      }
      if (sourceIndex < 0) sourceIndex = 0;
      final source = chapters.sources[sourceIndex];

      VideoEpisode? episode;
      if (history.episodeUrl.isNotEmpty) {
        for (final candidate in source.episodes) {
          if (candidate.pageUrl == history.episodeUrl) {
            episode = candidate;
            break;
          }
        }
      }
      episode ??= source.episodes.cast<VideoEpisode?>().firstWhere(
        (candidate) => candidate!.episodeIndex == history.episodeIndex,
        orElse: () => null,
      );
      episode ??= source.episodes.cast<VideoEpisode?>().firstWhere(
        (candidate) => candidate!.name == history.episodeName,
        orElse: () => null,
      );
      if (episode == null) return null;
      return VideoPlaybackSelection(
        rule: rule,
        searchItem: searchItem,
        chapters: chapters,
        episode: episode,
      );
    } catch (_) {
      return null;
    }
  }

  Widget _buildInfoRow(BuildContext context, bool compact) {
    final entries = <String>[
      if (item.airDate != null && item.airDate!.isNotEmpty)
        '首播 ${item.airDate}',
      if (item.episodeCount != null && item.episodeCount! > 0)
        '${item.episodeCount} 集',
      if (item.category.isNotEmpty) item.category,
    ];
    if (entries.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: entries
          .map(
            (entry) => Container(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 10 : 12,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                entry,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontSize: compact ? 11 : 12,
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _buildTags(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: item.tags
          .take(10)
          .map(
            (tag) => Text(
              '#$tag',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.9),
                fontSize: 12,
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _DetailActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color focusedColor;
  final VoidCallback onTap;

  const _DetailActionButton({
    required this.icon,
    required this.label,
    required this.focusedColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FocusableWidget(
      autofocus: true,
      onTap: onTap,
      builder: (context, focused) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 11),
          decoration: BoxDecoration(
            color: focused
                ? focusedColor
                : Colors.black.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: focused
                  ? focusedColor
                  : Colors.white.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: focused ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: focused ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
