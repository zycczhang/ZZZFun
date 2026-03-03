import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/anime_models.dart';
import '../services/anime_api_service.dart';
import '../services/anime_storage_service.dart';
class AnimeDetailController extends ChangeNotifier {
  final String url;
  final Map<String, dynamic>? initialPlaybackInfo;

  // --- 状态变量 ---
  AnimeDetail? detail;
  bool isLoading = true;
  bool isUrlLoading = false;
  bool isVideoBuffering = false;
  bool isFullScreen = false;
  bool showPlayerControls = false;
  bool isFavorited = false;

  // 播放器状态
  VideoPlayerController? videoController;
  String currentEpisodeName = "";
  int currentSourceIndex = 0;
  int selectedSourceIndex = 0;

  // 缓冲速度相关
  double bufferSpeed = 0.0;
  int _lastBufferBytes = 0;
  Timer? _speedCheckTimer;

  // 控制条隐藏计时器
  Timer? _controlHideTimer;

  // 快进快退防抖
  Timer? _seekDebounceTimer;
  Duration? targetSeekPosition;
  bool isSeekingUI = false;

  AnimeDetailController({required this.url, this.initialPlaybackInfo});

  // --- 初始化 ---
  Future<void> init() async {
    await checkFavoriteStatus();
    await _loadDetail();
  }

  Future<void> _loadDetail() async {
    try {
      detail = await AnimeApiService.fetchAnimeDetail(url);
      isLoading = false;
      notifyListeners();

      // 自动恢复进度逻辑（从 initialPlaybackInfo 或 数据库）
      await _handleResumeLogic();
    } catch (e) {
      isLoading = false;
      notifyListeners();
    }
  }

  // --- 视频播放核心逻辑 ---
  Future<void> playEpisode(Episode ep, int sourceIndex, {Duration? startPosition}) async {
    if (currentEpisodeName == ep.name && currentSourceIndex == sourceIndex && videoController != null && startPosition == null) return;

    isUrlLoading = true;
    currentEpisodeName = ep.name;
    currentSourceIndex = sourceIndex;
    isVideoBuffering = true;
    bufferSpeed = 0.0;
    notifyListeners();

    try {
      String realUrl = await AnimeApiService.getRealVideoUrl(ep.url);
      await videoController?.dispose();

      videoController = VideoPlayerController.networkUrl(Uri.parse(realUrl));
      await videoController!.initialize();

      if (startPosition != null && startPosition > Duration.zero) {
        await videoController!.seekTo(startPosition);
      }

      _listenToBuffering();
      videoController!.play();

      isUrlLoading = false;
      notifyListeners();
    } catch (e) {
      isUrlLoading = false;
      isVideoBuffering = false;
      notifyListeners();
    }
  }

  // --- 缓冲速度监听 ---
  void _listenToBuffering() {
    _speedCheckTimer?.cancel();
    _lastBufferBytes = 0;

    _speedCheckTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (videoController == null) return;

      int totalMs = 0;
      for (var range in videoController!.value.buffered) {
        totalMs += range.end.inMilliseconds - range.start.inMilliseconds;
      }

      bufferSpeed = (totalMs - _lastBufferBytes) * 1000.0;
      _lastBufferBytes = totalMs;

      // 检查缓冲状态
      bool currentBuffering = videoController!.value.isBuffering;
      if (currentBuffering != isVideoBuffering) {
        isVideoBuffering = currentBuffering;
      }
      notifyListeners();
    });
  }

  // --- 交互逻辑 ---
  void togglePlayPause() {
    if (videoController?.value.isInitialized == true) {
      videoController!.value.isPlaying ? videoController!.pause() : videoController!.play();
      resetControlTimer();
      notifyListeners();
    }
  }

  void toggleFullScreen() {
    isFullScreen = !isFullScreen;
    if (isFullScreen) resetControlTimer();
    notifyListeners();
  }

  void resetControlTimer() {
    _controlHideTimer?.cancel();
    showPlayerControls = true;
    notifyListeners();
    _controlHideTimer = Timer(const Duration(seconds: 3), () {
      showPlayerControls = false;
      notifyListeners();
    });
  }

  // 快进逻辑
  void handleKeySeek(bool forward) {
    if (videoController == null || !videoController!.value.isInitialized) return;

    if (targetSeekPosition == null) {
      targetSeekPosition = videoController!.value.position;
      isSeekingUI = true;
    }

    final step = const Duration(seconds: 5);
    targetSeekPosition = forward ? targetSeekPosition! + step : targetSeekPosition! - step;

    // 边界检查
    if (targetSeekPosition! < Duration.zero) targetSeekPosition = Duration.zero;
    if (targetSeekPosition! > videoController!.value.duration) targetSeekPosition = videoController!.value.duration;

    _seekDebounceTimer?.cancel();
    showPlayerControls = true;
    _controlHideTimer?.cancel();
    notifyListeners();

    _seekDebounceTimer = Timer(const Duration(milliseconds: 400), () async {
      isVideoBuffering = true;
      notifyListeners();
      await videoController!.seekTo(targetSeekPosition!);
      isSeekingUI = false;
      targetSeekPosition = null;
      resetControlTimer();
      notifyListeners();
    });
  }

  // --- 收藏与历史 ---
  Future<void> checkFavoriteStatus() async {
    isFavorited = await AnimeStorageService.isFavorite(url);
    notifyListeners();
  }

  Future<void> toggleFavorite() async {
    if (detail == null) return;
    if (isFavorited) {
      await AnimeStorageService.removeFavorite(url);
    } else {
      await AnimeStorageService.addFavorite(AnimeItem(
        title: detail!.title,
        imageUrl: detail!.imageUrl,
        url: url,
        note: "",
      ));
    }
    isFavorited = !isFavorited;
    notifyListeners();
  }

  Future<void> saveHistory() async {
    if (detail == null || videoController == null || !videoController!.value.isInitialized) return;

    final currentPos = videoController!.value.position;
    AnimeItem historyItem = AnimeItem(
      title: detail!.title,
      imageUrl: detail!.imageUrl,
      note: "上次播放到 $currentEpisodeName ${formatDuration(currentPos)}",
      url: url,
      playbackInfo: {
        'sourceIndex': currentSourceIndex,
        'episodeName': currentEpisodeName,
        'positionSeconds': currentPos.inSeconds,
      },
    );
    await AnimeStorageService.addHistory(historyItem);
  }

  // 内部辅助：恢复进度
  Future<void> _handleResumeLogic() async {
    int targetSourceIndex = 0;
    String targetEpName = "";
    int startSeconds = 0;
    bool shouldResume = false;

    if (initialPlaybackInfo != null) {
      targetSourceIndex = initialPlaybackInfo!['sourceIndex'] ?? 0;
      targetEpName = initialPlaybackInfo!['episodeName'] ?? "";
      startSeconds = initialPlaybackInfo!['positionSeconds'] ?? 0;
      shouldResume = true;
    } else {
      AnimeItem? historyItem = await AnimeStorageService.getHistoryItem(url);
      if (historyItem != null && historyItem.playbackInfo != null) {
        targetSourceIndex = historyItem.playbackInfo!['sourceIndex'] ?? 0;
        targetEpName = historyItem.playbackInfo!['episodeName'] ?? "";
        startSeconds = historyItem.playbackInfo!['positionSeconds'] ?? 0;
        shouldResume = true;
      }
    }

    if (shouldResume && detail!.playSources.isNotEmpty) {
      selectedSourceIndex = targetSourceIndex;
      var episodes = detail!.playSources[targetSourceIndex].episodes;
      try {
        var targetEp = episodes.firstWhere((e) => e.name == targetEpName);
        playEpisode(targetEp, targetSourceIndex, startPosition: Duration(seconds: startSeconds));
      } catch (_) {
        _playDefault();
      }
    } else {
      _playDefault();
    }
  }

  void _playDefault() {
    if (detail!.playSources.isNotEmpty && detail!.playSources[0].episodes.isNotEmpty) {
      playEpisode(detail!.playSources[0].episodes[0], 0);
    }
  }

  // 工具：格式化
  String formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return "${twoDigits(d.inHours)}:${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}";
    }
    return "${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}";
  }

  @override
  void dispose() {
    saveHistory(); // 销毁时自动保存
    _speedCheckTimer?.cancel();
    _controlHideTimer?.cancel();
    _seekDebounceTimer?.cancel();
    videoController?.dispose();
    super.dispose();
  }
}