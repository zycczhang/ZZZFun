import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/services.dart';
import 'anime_nav_widgets.dart';
import 'controllers/anime_detail_controller.dart';
import 'models/anime_models.dart';

class AnimeDetailPage extends StatefulWidget {
  final String url;
  final Map<String, dynamic>? initialPlaybackInfo;

  const AnimeDetailPage({super.key, required this.url, this.initialPlaybackInfo});

  @override
  State<AnimeDetailPage> createState() => _AnimeDetailPageState();
}

class _AnimeDetailPageState extends State<AnimeDetailPage> {
  late AnimeDetailController _controller;

  // 焦点控制保持在 UI 层
  final FocusNode _firstSourceNode = FocusNode();
  final FocusNode _playerFocusNode = FocusNode();
  final FocusNode _favoriteBtnNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // 初始化 Controller
    _controller = AnimeDetailController(
      url: widget.url,
      initialPlaybackInfo: widget.initialPlaybackInfo,
    );
    _controller.init();

    // 初始焦点请求
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_firstSourceNode.canRequestFocus) {
        _firstSourceNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose(); // Controller 会处理视频释放、历史记录保存等
    _firstSourceNode.dispose();
    _playerFocusNode.dispose();
    _favoriteBtnNode.dispose();
    super.dispose();
  }

  // 工具方法：字节格式化（可考虑移入 Controller 的公共工具类）
  String _formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond <= 0) return "0 KB/s";
    double kbPerSecond = bytesPerSecond / 1024;
    return kbPerSecond < 1024
        ? "${kbPerSecond.toStringAsFixed(1)} KB/s"
        : "${(kbPerSecond / 1024).toStringAsFixed(2)} MB/s";
  }

  @override
  Widget build(BuildContext context) {
    // 使用 ListenableBuilder 监听 Controller 变化
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, child) {
        return PopScope(
          canPop: !_controller.isFullScreen,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            if (_controller.isFullScreen) _controller.toggleFullScreen();
          },
          child: Scaffold(
            backgroundColor: const Color(0xFF0F1116),
            body: _controller.isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.orange))
                : _controller.isFullScreen
                ? _buildFullScreenPlayer()
                : Row(
              children: [
                Expanded(flex: 7, child: _buildLeftContent()),
                Expanded(flex: 3, child: _buildRightSideBar()),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- 全屏播放器 ---
  Widget _buildFullScreenPlayer() {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyUpEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _controller.handleKeySeek(false);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _controller.handleKeySeek(true);
            return KeyEventResult.handled;
          }
        }
        if (event is KeyDownEvent) {
          if ([LogicalKeyboardKey.select, LogicalKeyboardKey.enter, LogicalKeyboardKey.gameButtonA]
              .contains(event.logicalKey)) {
            if (!_controller.showPlayerControls) {
              _controller.resetControlTimer();
            } else {
              _controller.togglePlayPause();
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: FocusableWidget(
        onTap: () {
          _controller.showPlayerControls ? _controller.togglePlayPause() : _controller.resetControlTimer();
        },
        builder: (context, focused) {
          return Container(
            color: Colors.black,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_controller.videoController?.value.isInitialized == true)
                  Center(
                    child: AspectRatio(
                      aspectRatio: _controller.videoController!.value.aspectRatio,
                      child: VideoPlayer(_controller.videoController!),
                    ),
                  ),
                _buildPlayerStatusOverlay(),
                if (_controller.showPlayerControls) _buildPlayerControls(isFull: true),
              ],
            ),
          );
        },
      ),
    );
  }

  // --- 左侧内容区 ---
  Widget _buildLeftContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 播放器小窗口
          FocusableWidget(
            focusNode: _playerFocusNode,
            onTap: _controller.toggleFullScreen,
            builder: (context, focused) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: focused ? Colors.orange : Colors.transparent, width: 4),
                ),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      color: Colors.black,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (_controller.videoController?.value.isInitialized == true)
                            VideoPlayer(_controller.videoController!),
                          _buildPlayerStatusOverlay(),
                          if (focused && !_controller.isUrlLoading)
                            Container(color: Colors.black45, child: const Icon(Icons.fullscreen, color: Colors.white, size: 60)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 30),
          // 标题与收藏
          Row(
            children: [
              Expanded(
                child: Text(_controller.detail?.title ?? "",
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
              _buildFavoriteButton(),
            ],
          ),
          const SizedBox(height: 15),
          Text("正在播放：${_controller.currentEpisodeName}", style: const TextStyle(color: Colors.orange, fontSize: 16)),
          const SizedBox(height: 30),
          const Divider(color: Colors.white10),
          const Text("内容简介", style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          Text(_controller.detail?.introduction ?? "", style: const TextStyle(fontSize: 16, color: Colors.white70, height: 1.8)),
        ],
      ),
    );
  }

  // --- 状态叠加层（加载中/缓冲中） ---
  Widget _buildPlayerStatusOverlay() {
    if (!_controller.isUrlLoading && !(_controller.isVideoBuffering && !(_controller.videoController?.value.isPlaying ?? false))) {
      return const SizedBox.shrink();
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Colors.orange),
          const SizedBox(height: 16),
          Text(_controller.isUrlLoading ? "正在抓取资源..." : "缓冲中...", style: const TextStyle(color: Colors.white)),
          if (!_controller.isUrlLoading && _controller.bufferSpeed > 0)
            Text(_formatSpeed(_controller.bufferSpeed), style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // --- 播放器控制条 ---
  Widget _buildPlayerControls({required bool isFull}) {
    final realPos = _controller.videoController?.value.position ?? Duration.zero;
    final displayPos = _controller.targetSeekPosition ?? realPos;
    final totalDuration = _controller.videoController?.value.duration ?? Duration.zero;

    double progress = 0.0;
    if (totalDuration.inMilliseconds > 0) {
      progress = displayPos.inMilliseconds / totalDuration.inMilliseconds;
    }

    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withOpacity(0.8),
              Colors.transparent,
              Colors.black.withOpacity(0.5)
            ],
          ),
        ),
        child: Stack(
          children: [
            // 1. 主要控制界面（顶部标题和底部进度条）
            Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 顶部条：仅放返回键和剧集名称
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      if (isFull)
                        IconButton(
                          onPressed: _controller.toggleFullScreen,
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                        ),
                      Text(
                        _controller.currentEpisodeName,
                        style: const TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    ],
                  ),
                ),

                // 底部控制区
                Column(
                  children: [
                    // 自定义进度条
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Stack(
                        children: [
                          Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          FractionallySizedBox(
                            widthFactor: progress.clamp(0.0, 1.0),
                            child: Container(
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.orange,
                                borderRadius: BorderRadius.circular(2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.orange.withOpacity(0.5),
                                    blurRadius: 4,
                                  )
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      child: Row(
                        children: [
                          Icon(
                            _controller.videoController!.value.isPlaying
                                ? Icons.pause
                                : Icons.play_arrow,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            "${_controller.formatDuration(displayPos)} / ${_controller.formatDuration(totalDuration)}",
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: Icon(
                              isFull ? Icons.fullscreen_exit : Icons.fullscreen,
                              color: Colors.white,
                            ),
                            onPressed: _controller.toggleFullScreen,
                          ),
                        ],
                      ),
                    )
                  ],
                ),
              ],
            ),

            // 2. 快进时间提示框（上方水平居中）
            if (_controller.isSeekingUI)
              Align(
                alignment: const Alignment(0, -0.5), // 0 表示水平居中，-0.5 表示在垂直中心偏上的位置
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _controller.formatDuration(displayPos),
                    style: const TextStyle(
                      color: Colors.orange,
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // --- 收藏按钮 ---
  Widget _buildFavoriteButton() {
    return FocusableWidget(
      focusNode: _favoriteBtnNode,
      onTap: _controller.toggleFavorite,
      builder: (context, focused) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: focused ? Colors.white : (_controller.isFavorited ? Colors.orange : Colors.white10),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Icon(_controller.isFavorited ? Icons.favorite : Icons.favorite_border, color: focused ? Colors.black : Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(_controller.isFavorited ? "已收藏" : "收藏", style: TextStyle(color: focused ? Colors.black : Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
        );
      },
    );
  }

  // --- 右侧选集栏 ---
  Widget _buildRightSideBar() {
    return Container(
      color: const Color(0xFF161920),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 50, 20, 10),
            child: Text("选集播放", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          // 播放源切换
          SizedBox(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 15),
              itemCount: _controller.detail?.playSources.length ?? 0,
              itemBuilder: (context, index) {
                bool isSelected = _controller.selectedSourceIndex == index;
                return FocusableWidget(
                  focusNode: index == 0 ? _firstSourceNode : null,
                  onTap: () => setState(() => _controller.selectedSourceIndex = index),
                  builder: (context, focused) => Container(
                    alignment: Alignment.center,
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    decoration: BoxDecoration(
                      color: focused ? Colors.orange : (isSelected ? Colors.orange.withOpacity(0.2) : Colors.white10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_controller.detail!.playSources[index].sourceName, style: TextStyle(color: focused ? Colors.black : Colors.white)),
                  ),
                );
              },
            ),
          ),
          // 集数网格
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(20),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 2.5),
              itemCount: _controller.detail?.playSources[_controller.selectedSourceIndex].episodes.length ?? 0,
              itemBuilder: (context, index) {
                var ep = _controller.detail!.playSources[_controller.selectedSourceIndex].episodes[index];
                bool isPlaying = _controller.currentSourceIndex == _controller.selectedSourceIndex && _controller.currentEpisodeName == ep.name;
                return FocusableWidget(
                  onTap: () => _controller.playEpisode(ep, _controller.selectedSourceIndex),
                  builder: (context, focused) {
                    return Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: focused ? Colors.white : (isPlaying ? Colors.orange.withOpacity(0.1) : Colors.white.withOpacity(0.03)),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: focused ? Colors.white : (isPlaying ? Colors.orange : Colors.white10)),
                      ),
                      child: Text(ep.name, style: TextStyle(color: focused ? Colors.black : (isPlaying ? Colors.orange : Colors.white))),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}