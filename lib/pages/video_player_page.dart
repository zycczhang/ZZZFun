import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../anime_nav_widgets.dart';
import '../models/anime_models.dart';
import '../models/video_source_models.dart';
import '../services/video_resource_service.dart';
import '../services/video_source_resolver.dart';
import 'video_source_picker_dialog.dart';

class VideoPlayerPage extends StatefulWidget {
  final AnimeItem item;
  final VideoPlaybackSelection selection;
  final VideoResourceService resourceService;

  const VideoPlayerPage({
    super.key,
    required this.item,
    required this.selection,
    required this.resourceService,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  final VideoSourceResolver _resolver = VideoSourceResolver();
  late VideoPlaybackSelection _selection;
  VideoPlayerController? _controller;
  Object? _error;
  bool _loading = true;
  bool _fullscreen = false;
  bool _showFullscreenControls = false;
  int _loadGeneration = 0;
  int _selectedSourceIndex = 0;

  final FocusNode _playerFocusNode = FocusNode(debugLabel: '播放器');
  final FocusNode _previousFocusNode = FocusNode(debugLabel: '上一集');
  final FocusNode _rewindFocusNode = FocusNode(debugLabel: '快退');
  final FocusNode _playPauseFocusNode = FocusNode(debugLabel: '播放暂停');
  final FocusNode _progressFocusNode = FocusNode(debugLabel: '播放进度');
  final FocusNode _forwardFocusNode = FocusNode(debugLabel: '快进');
  final FocusNode _nextFocusNode = FocusNode(debugLabel: '下一集');
  final FocusNode _changeSourceFocusNode = FocusNode(debugLabel: '更换播放源');
  final FocusNode _fullscreenFocusNode = FocusNode(debugLabel: '全屏');
  final Map<int, FocusNode> _sourceFocusNodes = {};
  final Map<String, FocusNode> _episodeFocusNodes = {};

  Timer? _seekDebounceTimer;
  Timer? _controlHideTimer;
  Duration? _targetSeekPosition;
  bool _isSeeking = false;

  @override
  void initState() {
    super.initState();
    _selection = widget.selection;
    _selectedSourceIndex = _findSourceIndex(_selection.episode);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _playerFocusNode.requestFocus();
    });
    unawaited(_loadEpisode(_selection.episode));
  }

  @override
  void dispose() {
    _seekDebounceTimer?.cancel();
    _controller?.dispose();
    _playerFocusNode.dispose();
    _previousFocusNode.dispose();
    _rewindFocusNode.dispose();
    _playPauseFocusNode.dispose();
    _progressFocusNode.dispose();
    _forwardFocusNode.dispose();
    _nextFocusNode.dispose();
    _changeSourceFocusNode.dispose();
    _fullscreenFocusNode.dispose();
    _controlHideTimer?.cancel();
    for (final node in _sourceFocusNodes.values) {
      node.dispose();
    }
    for (final node in _episodeFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  int _findSourceIndex(VideoEpisode episode) {
    final sources = _selection.chapters.sources;
    for (var index = 0; index < sources.length; index++) {
      if (sources[index].episodes.any(
        (candidate) =>
            candidate.pageUrl == episode.pageUrl &&
            candidate.name == episode.name,
      )) {
        return index;
      }
    }
    return 0;
  }

  FocusNode _sourceFocusNode(int index) {
    return _sourceFocusNodes.putIfAbsent(
      index,
      () => FocusNode(debugLabel: '播放源 $index'),
    );
  }

  FocusNode _episodeFocusNode(int sourceIndex, int episodeIndex) {
    final key = '$sourceIndex:$episodeIndex';
    return _episodeFocusNodes.putIfAbsent(
      key,
      () => FocusNode(debugLabel: '选集 $key'),
    );
  }

  Future<void> _loadEpisode(VideoEpisode episode) async {
    final generation = ++_loadGeneration;
    final oldController = _controller;
    _controller = null;
    _seekDebounceTimer?.cancel();
    _targetSeekPosition = null;
    _isSeeking = false;
    await oldController?.dispose();
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    if (_fullscreen) {
      _requestPlayerFocus();
      _startControlHideTimer();
    }

    try {
      final resolved = await _resolver.resolve(
        episode,
        useLegacyParser: _selection.rule.useLegacyParser,
      );
      if (!mounted || generation != _loadGeneration) return;
      final controller = VideoPlayerController.networkUrl(
        resolved.uri,
        formatHint: resolved.isHls ? VideoFormat.hls : null,
        httpHeaders: resolved.headers,
      );
      await controller.initialize();
      if (!mounted || generation != _loadGeneration) {
        await controller.dispose();
        return;
      }
      controller.addListener(_onVideoChanged);
      setState(() {
        _controller = controller;
        _loading = false;
        _error = null;
      });
      await controller.play();
      if (_fullscreen) {
        _showControlsAndFocus(_progressFocusNode);
      } else {
        _requestPlayerFocus();
      }
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = error;
      });
      _requestPlayerFocus();
    }
  }

  void _onVideoChanged() {
    if (!mounted) return;
    final controller = _controller;
    if (controller?.value.hasError == true && _error == null) {
      setState(() => _error = controller!.value.errorDescription);
    }
  }

  Future<void> _openSourcePicker() async {
    final next = await showDialog<VideoPlaybackSelection>(
      context: context,
      barrierDismissible: false,
      builder: (context) => VideoSourcePickerDialog(
        item: widget.item,
        resourceService: widget.resourceService,
      ),
    );
    if (next == null || !mounted) return;
    setState(() {
      _selection = next;
      _selectedSourceIndex = _findSourceIndex(next.episode);
    });
    await _loadEpisode(next.episode);
  }

  void _selectEpisode(VideoEpisode episode, int sourceIndex) {
    setState(() {
      _selectedSourceIndex = sourceIndex;
      _selection = VideoPlaybackSelection(
        rule: _selection.rule,
        searchItem: _selection.searchItem,
        chapters: _selection.chapters,
        episode: episode,
      );
    });
    unawaited(_loadEpisode(episode));
  }

  void _selectSource(int index) {
    if (index < 0 || index >= _selection.chapters.sources.length) return;
    setState(() => _selectedSourceIndex = index);
  }

  void _selectAdjacentEpisode(int delta) {
    final sources = _selection.chapters.sources;
    if (sources.isEmpty) return;
    final sourceIndex = _safeSourceIndex;
    final episodes = sources[sourceIndex].episodes;
    final currentIndex = episodes.indexWhere(
      (episode) =>
          episode.pageUrl == _selection.episode.pageUrl &&
          episode.name == _selection.episode.name,
    );
    if (currentIndex < 0) return;
    final nextIndex = currentIndex + delta;
    if (nextIndex < 0 || nextIndex >= episodes.length) return;
    _selectEpisode(episodes[nextIndex], sourceIndex);
  }

  bool _hasAdjacentEpisode(int delta) {
    final sources = _selection.chapters.sources;
    if (sources.isEmpty) return false;
    final episodes = sources[_safeSourceIndex].episodes;
    final currentIndex = episodes.indexWhere(
      (episode) =>
          episode.pageUrl == _selection.episode.pageUrl &&
          episode.name == _selection.episode.name,
    );
    final nextIndex = currentIndex + delta;
    return currentIndex >= 0 && nextIndex >= 0 && nextIndex < episodes.length;
  }

  void _togglePlayPause() {
    final controller = _controller;
    if (controller?.value.isInitialized != true) return;
    if (controller!.value.isPlaying) {
      unawaited(controller.pause());
    } else {
      unawaited(controller.play());
    }
    setState(() {});
  }

  void _enterFullscreen() {
    if (_fullscreen) return;
    _controlHideTimer?.cancel();
    setState(() {
      _fullscreen = true;
      _showFullscreenControls = true;
    });
    _showControlsAndFocus(_progressFocusNode);
  }

  void _exitFullscreen() {
    if (!_fullscreen) return;
    _controlHideTimer?.cancel();
    setState(() {
      _fullscreen = false;
      _showFullscreenControls = false;
    });
    _requestPlayerFocus();
  }

  void _startControlHideTimer() {
    if (!_fullscreen) return;
    _controlHideTimer?.cancel();
    _controlHideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || !_fullscreen) return;
      setState(() => _showFullscreenControls = false);
      _requestPlayerFocus();
    });
  }

  void _markFullscreenInteraction() {
    if (!_fullscreen) return;
    if (!_showFullscreenControls) {
      setState(() => _showFullscreenControls = true);
    }
    _startControlHideTimer();
  }

  void _showControlsAndFocus(FocusNode focusNode) {
    _markFullscreenInteraction();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _fullscreen && _showFullscreenControls) {
        focusNode.requestFocus();
      }
    });
  }

  void _requestPlayerFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _playerFocusNode.canRequestFocus) {
        _playerFocusNode.requestFocus();
      }
    });
  }

  void _handlePlayerActivate() {
    if (_error != null) {
      unawaited(_loadEpisode(_selection.episode));
      return;
    }
    if (!_fullscreen) {
      _enterFullscreen();
    } else if (!_showFullscreenControls) {
      _showControlsAndFocus(_progressFocusNode);
    } else {
      _togglePlayPause();
      _markFullscreenInteraction();
    }
  }

  KeyEventResult _handlePlayerKey(FocusNode node, KeyEvent event) {
    if (_isKeyPress(event)) {
      if (_fullscreen) _markFullscreenInteraction();
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        if (_fullscreen) _handleKeySeek(false);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        if (_fullscreen) {
          _handleKeySeek(true);
        } else {
          _focusFirstSource();
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        if (_fullscreen) {
          _showControlsAndFocus(_progressFocusNode);
        } else {
          _changeSourceFocusNode.requestFocus();
        }
        return KeyEventResult.handled;
      }
      if (_isActivationKey(event)) {
        _handlePlayerActivate();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleControlKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      _markFullscreenInteraction();
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _progressFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleProgressKey(FocusNode node, KeyEvent event) {
    if (_isKeyPress(event)) {
      _markFullscreenInteraction();
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _handleKeySeek(false);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _handleKeySeek(true);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _focusFirstPlaybackControl();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _playerFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleSourceKey(
    FocusNode node,
    KeyEvent event,
    int sourceIndex,
  ) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _playerFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _focusFirstEpisode(sourceIndex: sourceIndex);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft && sourceIndex > 0) {
        _focusSource(sourceIndex - 1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _focusSource(sourceIndex + 1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
          sourceIndex == 0) {
        _playerFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleEpisodeKey(
    FocusNode node,
    KeyEvent event,
    int sourceIndex,
    int episodeIndex,
  ) {
    if (event is KeyDownEvent) {
      final episodeCount =
          _selection.chapters.sources[sourceIndex].episodes.length;
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        if (episodeIndex >= 2) {
          _episodeFocusNode(sourceIndex, episodeIndex - 2).requestFocus();
        } else {
          _sourceFocusNode(sourceIndex).requestFocus();
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
          episodeIndex + 2 < episodeCount) {
        _episodeFocusNode(sourceIndex, episodeIndex + 2).requestFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
          episodeIndex % 2 == 1) {
        _episodeFocusNode(sourceIndex, episodeIndex - 1).requestFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
          episodeIndex % 2 == 0) {
        _playerFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
          episodeIndex % 2 == 0 &&
          episodeIndex + 1 < episodeCount) {
        _episodeFocusNode(sourceIndex, episodeIndex + 1).requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  bool _isKeyPress(KeyEvent event) =>
      event is KeyDownEvent || event is KeyRepeatEvent;

  bool _isActivationKey(KeyEvent event) =>
      event.logicalKey == LogicalKeyboardKey.enter ||
      event.logicalKey == LogicalKeyboardKey.select ||
      event.logicalKey == LogicalKeyboardKey.gameButtonA ||
      event.logicalKey == LogicalKeyboardKey.mediaPlayPause;

  void _handleKeySeek(bool forward) {
    final controller = _controller;
    if (controller?.value.isInitialized != true) return;
    final duration = controller!.value.duration;
    if (duration <= Duration.zero) return;

    final current = _targetSeekPosition ?? controller.value.position;
    final step = const Duration(seconds: 5);
    var next = forward ? current + step : current - step;
    if (next < Duration.zero) next = Duration.zero;
    if (next > duration) next = duration;

    _seekDebounceTimer?.cancel();
    setState(() {
      _targetSeekPosition = next;
      _isSeeking = true;
    });
    _seekDebounceTimer = Timer(const Duration(milliseconds: 350), _commitSeek);
  }

  Future<void> _commitSeek() async {
    final target = _targetSeekPosition;
    final controller = _controller;
    if (target == null || controller?.value.isInitialized != true) return;
    await controller!.seekTo(target);
    if (!mounted) return;
    setState(() {
      _targetSeekPosition = null;
      _isSeeking = false;
    });
  }

  void _seekFromSlider(double value) {
    final controller = _controller;
    if (controller?.value.isInitialized != true) return;
    _markFullscreenInteraction();
    _seekDebounceTimer?.cancel();
    _targetSeekPosition = null;
    _isSeeking = false;
    unawaited(controller!.seekTo(Duration(milliseconds: value.round())));
  }

  void _focusFirstEpisode({int? sourceIndex}) {
    final sources = _selection.chapters.sources;
    if (sources.isEmpty) return;
    final index = sourceIndex ?? _safeSourceIndex;
    final episodes = sources[index].episodes;
    if (episodes.isNotEmpty) {
      _episodeFocusNode(index, 0).requestFocus();
    } else {
      _sourceFocusNode(index).requestFocus();
    }
  }

  void _focusFirstPlaybackControl() {
    if (_hasAdjacentEpisode(-1)) {
      _previousFocusNode.requestFocus();
    } else {
      _rewindFocusNode.requestFocus();
    }
  }

  void _focusFirstSource() {
    if (_selection.chapters.sources.isNotEmpty) {
      _sourceFocusNode(_safeSourceIndex).requestFocus();
    }
  }

  void _focusSource(int sourceIndex) {
    if (sourceIndex >= 0 && sourceIndex < _selection.chapters.sources.length) {
      _sourceFocusNode(sourceIndex).requestFocus();
    }
  }

  KeyEventResult _handleNormalChangeSourceKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _playerFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _playerFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _focusFirstSource();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  int get _safeSourceIndex {
    final sourceCount = _selection.chapters.sources.length;
    if (sourceCount == 0) return 0;
    return _selectedSourceIndex.clamp(0, sourceCount - 1);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _fullscreen) _exitFullscreen();
      },
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.escape ||
                  event.logicalKey == LogicalKeyboardKey.goBack) &&
              _fullscreen) {
            _exitFullscreen();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Scaffold(
          backgroundColor: const Color(0xFF0E1015),
          body: FocusTraversalGroup(
            policy: ReadingOrderTraversalPolicy(),
            child: _fullscreen
                ? _buildFullscreenPlayer()
                : Row(
                    children: [
                      Expanded(flex: 7, child: _buildMainColumn()),
                      Expanded(flex: 3, child: _buildEpisodePanel()),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildFullscreenPlayer() {
    return ColoredBox(
      color: Colors.black,
      child: _buildPlayerSurface(fullscreen: true),
    );
  }

  Widget _buildMainColumn() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 44),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1500),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _buildPlayerSurface(fullscreen: false),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 42,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                _buildTextControl(
                  focusNode: _changeSourceFocusNode,
                  icon: Icons.alt_route_rounded,
                  label: '换源',
                  onTap: _openSourcePicker,
                  onKeyEvent: _handleNormalChangeSourceKey,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerSurface({required bool fullscreen}) {
    final controller = _controller;
    final video = controller?.value.isInitialized == true
        ? Center(
            child: AspectRatio(
              aspectRatio: controller!.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          )
        : const ColoredBox(color: Colors.black);

    final content = Stack(
      fit: StackFit.expand,
      children: [
        video,
        if (controller != null)
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: controller,
            builder: (context, value, child) => Stack(
              fit: StackFit.expand,
              children: [
                _buildPlayerStatus(value),
                if (fullscreen &&
                    _showFullscreenControls &&
                    value.isInitialized &&
                    !_loading)
                  _buildPlaybackControls(value, fullscreen: fullscreen),
              ],
            ),
          )
        else
          _buildPlayerStatus(null),
      ],
    );

    return FocusableWidget(
      focusNode: _playerFocusNode,
      autofocus: true,
      onTap: _handlePlayerActivate,
      onKeyEvent: _handlePlayerKey,
      builder: (context, focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          color: Colors.black,
          border: fullscreen
              ? null
              : Border.all(
                  color: focused
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                  width: 3,
                ),
        ),
        child: content,
      ),
    );
  }

  Widget _buildPlayerStatus(VideoPlayerValue? value) {
    if (_error != null) return _buildPlayerError();
    if (_loading || value?.isBuffering == true) {
      return Container(
        color: Colors.black54,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildPlayerError() {
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.white70, size: 38),
          const SizedBox(height: 10),
          const Text('播放失败', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            _error.toString(),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          FocusableWidget(
            onTap: () => unawaited(_loadEpisode(_selection.episode)),
            builder: (context, focused) =>
                _buildSmallButton(Icons.refresh, '重试', focused),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaybackControls(
    VideoPlayerValue value, {
    required bool fullscreen,
  }) {
    final duration = value.duration.inMilliseconds;
    final actualPosition = value.position.inMilliseconds
        .clamp(0, duration == 0 ? 1 : duration)
        .toInt();
    final displayPosition =
        (_targetSeekPosition ?? Duration(milliseconds: actualPosition))
            .inMilliseconds
            .clamp(0, duration == 0 ? 1 : duration)
            .toInt();
    final max = (duration == 0 ? 1 : duration).toDouble();

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 34, 14, 10),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Color(0xE6000000)],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FocusableWidget(
              focusNode: _progressFocusNode,
              onKeyEvent: _handleProgressKey,
              builder: (context, focused) => SizedBox(
                height: 32,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: focused ? 5 : 3,
                    thumbShape: RoundSliderThumbShape(
                      enabledThumbRadius: focused ? 7 : 5,
                    ),
                    activeTrackColor: focused
                        ? Theme.of(context).colorScheme.primary
                        : Colors.white,
                    inactiveTrackColor: Colors.white30,
                    thumbColor: Theme.of(context).colorScheme.primary,
                    overlayColor: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.18),
                  ),
                  child: ExcludeFocus(
                    child: Slider(
                      value: displayPosition.toDouble(),
                      max: max,
                      onChanged: _seekFromSlider,
                    ),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                _buildIconControl(
                  focusNode: _previousFocusNode,
                  icon: Icons.skip_previous_rounded,
                  label: '上一集',
                  enabled: _hasAdjacentEpisode(-1),
                  onTap: () => _selectAdjacentEpisode(-1),
                  rightFocusNode: _rewindFocusNode,
                ),
                _buildIconControl(
                  focusNode: _rewindFocusNode,
                  icon: Icons.replay_10_rounded,
                  label: '快退 5 秒',
                  onTap: () => _handleKeySeek(false),
                  onKeyEvent: _handleControlKey,
                  leftFocusNode: _previousFocusNode,
                  rightFocusNode: _playPauseFocusNode,
                ),
                _buildIconControl(
                  focusNode: _playPauseFocusNode,
                  icon: value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  label: value.isPlaying ? '暂停' : '播放',
                  onTap: _togglePlayPause,
                  onKeyEvent: _handleControlKey,
                  large: true,
                  leftFocusNode: _rewindFocusNode,
                  rightFocusNode: _forwardFocusNode,
                ),
                _buildIconControl(
                  focusNode: _forwardFocusNode,
                  icon: Icons.forward_10_rounded,
                  label: '快进 5 秒',
                  onTap: () => _handleKeySeek(true),
                  onKeyEvent: _handleControlKey,
                  leftFocusNode: _playPauseFocusNode,
                  rightFocusNode: _nextFocusNode,
                ),
                _buildIconControl(
                  focusNode: _nextFocusNode,
                  icon: Icons.skip_next_rounded,
                  label: '下一集',
                  enabled: _hasAdjacentEpisode(1),
                  onTap: () => _selectAdjacentEpisode(1),
                  leftFocusNode: _forwardFocusNode,
                  rightFocusNode: _fullscreenFocusNode,
                ),
                const SizedBox(width: 8),
                Text(
                  '${_formatDuration(Duration(milliseconds: displayPosition))} / '
                  '${_formatDuration(value.duration)}',
                  style: TextStyle(
                    color: _isSeeking ? Colors.amber : Colors.white,
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const Spacer(),
                _buildIconControl(
                  focusNode: _fullscreenFocusNode,
                  icon: fullscreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  label: fullscreen ? '退出全屏' : '全屏',
                  onTap: _exitFullscreen,
                  onKeyEvent: _handleControlKey,
                  leftFocusNode: _nextFocusNode,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEpisodePanel() {
    final sources = _selection.chapters.sources;
    final safeIndex = _safeSourceIndex;
    final episodes = sources.isEmpty
        ? const <VideoEpisode>[]
        : sources[safeIndex].episodes;

    return ColoredBox(
      color: const Color(0xFF15181F),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 28, 20, 12),
            child: Text(
              '选集播放',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: sources.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FocusableWidget(
                  focusNode: _sourceFocusNode(index),
                  onTap: () => _selectSource(index),
                  onKeyEvent: (node, event) =>
                      _handleSourceKey(node, event, index),
                  builder: (context, focused) => Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: focused
                          ? Theme.of(context).colorScheme.primary
                          : index == safeIndex
                          ? Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.22)
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      sources[index].name,
                      style: TextStyle(
                        color: focused ? Colors.black : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: episodes.isEmpty
                ? Center(
                    child: Text(
                      '暂无选集',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 2.4,
                        ),
                    itemCount: episodes.length,
                    itemBuilder: (context, index) {
                      final episode = episodes[index];
                      final playing =
                          episode.pageUrl == _selection.episode.pageUrl &&
                          episode.name == _selection.episode.name;
                      return FocusableWidget(
                        focusNode: _episodeFocusNode(safeIndex, index),
                        onTap: () => _selectEpisode(episode, safeIndex),
                        onKeyEvent: (node, event) =>
                            _handleEpisodeKey(node, event, safeIndex, index),
                        builder: (context, focused) => AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: focused
                                ? Colors.white
                                : playing
                                ? Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.18)
                                : Colors.white.withValues(alpha: 0.035),
                            border: Border.all(
                              color: focused
                                  ? Colors.white
                                  : playing
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.white.withValues(alpha: 0.1),
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            episode.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: focused ? Colors.black : Colors.white,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconControl({
    required FocusNode focusNode,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    KeyEventResult Function(FocusNode node, KeyEvent event)? onKeyEvent,
    bool enabled = true,
    bool large = false,
    FocusNode? leftFocusNode,
    FocusNode? rightFocusNode,
  }) {
    return Tooltip(
      message: label,
      child: FocusableWidget(
        focusNode: focusNode,
        enabled: enabled,
        onTap: enabled
            ? () {
                _markFullscreenInteraction();
                onTap();
              }
            : null,
        onKeyEvent: (node, event) {
          _markFullscreenInteraction();
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.arrowLeft &&
              leftFocusNode != null) {
            leftFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.arrowRight &&
              rightFocusNode != null) {
            rightFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          return onKeyEvent?.call(node, event) ?? KeyEventResult.ignored;
        },
        builder: (context, focused) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: large ? 48 : 42,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: focused
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: large ? 27 : 22,
            color: !enabled
                ? Colors.white24
                : focused
                ? Colors.black
                : Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildTextControl({
    required FocusNode focusNode,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    KeyEventResult Function(FocusNode node, KeyEvent event)? onKeyEvent,
  }) {
    return FocusableWidget(
      focusNode: focusNode,
      onTap: () {
        _markFullscreenInteraction();
        onTap();
      },
      onKeyEvent: (node, event) {
        _markFullscreenInteraction();
        return onKeyEvent?.call(node, event) ?? KeyEventResult.ignored;
      },
      builder: (context, focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: focused
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 21, color: focused ? Colors.black : Colors.white),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: focused ? Colors.black : Colors.white,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallButton(IconData icon, String label, bool focused) {
    final primary = Theme.of(context).colorScheme.primary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: focused ? primary : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: focused ? Colors.black : Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: focused ? Colors.black : Colors.white),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}
