import 'dart:async';
import 'dart:math'; // 引入 math 库用于 min 计算
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'anime_nav_widgets.dart';
import 'package:flutter/services.dart';
import 'models/anime_models.dart';
import 'services/anime_api_service.dart';
import 'services/anime_storage_service.dart';
class AnimeDetailPage extends StatefulWidget {
  final String url;
  // 新增：接收从历史记录传来的播放信息
  final Map<String, dynamic>? initialPlaybackInfo;

  const AnimeDetailPage({super.key, required this.url, this.initialPlaybackInfo});

  @override
  State<AnimeDetailPage> createState() => _AnimeDetailPageState();
}

class _AnimeDetailPageState extends State<AnimeDetailPage> {
  AnimeDetail? _detail;
  bool _isLoading = true;
  bool _isUrlLoading = false;
  int _selectedSourceIndex = 0;

  // --- 新增：防抖寻道相关变量 ---
  Timer? _seekDebounceTimer; // 延迟执行seek的计时器
  Duration? _targetSeekPosition; // 记录当前UI显示的虚拟进度
  bool _isSeekingUI = false; // 标记是否处于按键调整进度的状态

  VideoPlayerController? _videoController;
  String _currentEpisodeName = "";
  // 新增：记录当前播放集数所属的播放源索引
  int _currentSourceIndex = 0;
  bool _isFullScreen = false;
  bool _showPlayerControls = false;

  // --- 修改开始：替换缓冲进度为下载速率 ---
  bool _isVideoBuffering = false;
  // 记录上一次检查时的缓冲字节数
  int _lastBufferBytes = 0;
  // 当前的下载速度 (Bytes/s)
  double _bufferSpeed = 0.0;
  // 用于计算速度的定时器
  Timer? _speedCheckTimer;
  // --- 修改结束 ---

  final FocusNode _currentEpisodeNode = FocusNode();
  final FocusNode _firstSourceNode = FocusNode();
  // 新增：播放器专属焦点节点
  final FocusNode _playerFocusNode = FocusNode();

  // 新增：收藏按钮的焦点
  final FocusNode _favoriteBtnNode = FocusNode();

  Timer? _controlHideTimer;
  // 移除原有的 _bufferCheckTimer，因为现在使用 _speedCheckTimer 和监听器

  // 新增：收藏状态
  bool _isFavorited = false;

  // 新增：标记是否是从历史记录恢复的首次加载
  bool _isResumeLoading = false;

  // 工具方法：将Duration格式化为 mm:ss 或 hh:mm:ss
  String _formatDuration(Duration? duration) {
    if (duration == null) return "00:00";

    String twoDigits(int n) => n.toString().padLeft(2, '0');
    int hours = duration.inHours;
    int minutes = duration.inMinutes.remainder(60);
    int seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return "${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}";
    } else {
      return "${twoDigits(minutes)}:${twoDigits(seconds)}";
    }
  }

  // 工具方法：将字节速率格式化为 KB/s 或 MB/s
  String _formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond <= 0) return "0 KB/s";

    // 转换为 KB/s
    double kbPerSecond = bytesPerSecond / 1024;

    if (kbPerSecond < 1024) {
      return "${kbPerSecond.toStringAsFixed(1)} KB/s";
    } else {
      // 转换为 MB/s
      double mbPerSecond = kbPerSecond / 1024;
      return "${mbPerSecond.toStringAsFixed(2)} MB/s";
    }
  }

  // 新增：计算当前已缓冲的总字节数
  int _getTotalBufferedBytes() {
    if (_videoController == null ||
        _videoController!.value.buffered.isEmpty ||
        _videoController!.value.duration.inMilliseconds == 0) {
      return 0;
    }

    // 视频总时长（毫秒）
    final totalDurationMs = _videoController!.value.duration.inMilliseconds;

    // 累加所有缓冲区间的时间长度
    int totalBufferedMs = 0;
    for (var range in _videoController!.value.buffered) {
      totalBufferedMs += range.end.inMilliseconds - range.start.inMilliseconds;
    }

    return totalBufferedMs; // 返回毫秒数作为“虚拟字节”单位
  }

  // 修改：监听视频缓冲状态并计算速率
  void _listenToVideoBuffering() {
    if (_videoController == null) return;

    // 重置状态
    _lastBufferBytes = 0;
    _bufferSpeed = 0.0;
    _speedCheckTimer?.cancel();

    // 1. 启动定时器：每秒计算一次速度
    _speedCheckTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _videoController == null) {
        timer.cancel();
        return;
      }

      // 获取当前的“虚拟字节数”（即缓冲时长毫秒数）
      int currentBufferBytes = _getTotalBufferedBytes();

      // 计算增量
      int deltaBytes = currentBufferBytes - _lastBufferBytes;

      // 更新速度 (这里我们将毫秒数直接当作字节数来显示速率单位，实际上应该是字节)
      // 为了显示好看，我们假设 1ms 缓冲时长 ≈ 1KB 数据（这是一个为了显示的估算值）
      setState(() {
        // 乘以一个系数（例如 1000）让数值看起来像真实的下载速度，而不是 0.几
        // 这里的数值是模拟的，因为无法获取真实码率
        _bufferSpeed = deltaBytes * 1000.0;
        _lastBufferBytes = currentBufferBytes;
      });
    });

    // 2. 监听控制器状态（用于判断是否正在缓冲）
    _videoController!.addListener(() {
      if (mounted) {
        setState(() {
          _isVideoBuffering = _videoController!.value.isBuffering;
        });
      }
    });
  }

  void _handleKeySeek(bool forward) {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return;
    }
    // 1. 如果是第一次按下，初始化虚拟进度为当前视频进度
    if (_targetSeekPosition == null) {
      _targetSeekPosition = _videoController!.value.position;
      _isSeekingUI = true;
    }
    // 2. 计算新的虚拟进度
    // 单次按键步进，长按时这个函数会被疯狂调用，所以步进不要太大，3秒或5秒比较合适
    final step = const Duration(seconds: 5);
    final totalDuration = _videoController!.value.duration;

    var newPos = forward
        ? _targetSeekPosition! + step
        : _targetSeekPosition! - step;
    // 边界检查
    if (newPos < Duration.zero) newPos = Duration.zero;
    if (newPos > totalDuration) newPos = totalDuration;
    // 3. 取消上一次未执行的 seek 操作
    _seekDebounceTimer?.cancel();
    // 4. 立即更新 UI（只更新数字显示，不卡顿）
    setState(() {
      _targetSeekPosition = newPos;
      _showPlayerControls = true; // 调整进度时强制显示控制条
      _controlHideTimer?.cancel(); // 暂停控制条隐藏倒计时
    });
    // 5. 设置延时，如果用户 400ms 内没有再次按键，则执行真正的跳转
    _seekDebounceTimer = Timer(const Duration(milliseconds: 400), () {
      _executeSeek();
    });
  }

  // 执行真正的跳转
  void _executeSeek() {
    if (_videoController != null && _targetSeekPosition != null) {
      // 显示缓冲状态
      setState(() {
        _isVideoBuffering = true;
        _bufferSpeed = 0.0;
      });
      _videoController!.seekTo(_targetSeekPosition!).then((_) {
        // 跳转完成后
        if (mounted) {
          setState(() {
            _isSeekingUI = false; // 退出虚拟进度模式
            _targetSeekPosition = null;
          });
          // 重新开始控制条隐藏倒计时
          _resetControlTimer();
        }
      });
    }
  }

  // 新增：保存历史记录逻辑
  Future<void> _saveHistory() async {
    if (_detail == null || _videoController == null || !_videoController!.value.isInitialized) return;

    final currentPos = _videoController!.value.position;
    // 如果播放时间太短（比如小于10秒），可能不值得记录，看需求，这里全记录

    // 构造备注信息： "上次播放到 1集 23:11"
    String timeStr = _formatDuration(currentPos);
    String note = "上次播放到 $_currentEpisodeName $timeStr";

    AnimeItem historyItem = AnimeItem(
      title: _detail!.title,
      imageUrl: _detail!.imageUrl,
      note: note, // UI显示的备注
      url: widget.url,
      playbackInfo: {
        'sourceIndex': _currentSourceIndex,
        'episodeName': _currentEpisodeName,
        'positionSeconds': currentPos.inSeconds,
      },
    );

    await AnimeStorageService.addHistory(historyItem);
    print("已保存历史记录: $note");
  }

  // 新增：检查收藏状态
  void _checkFavoriteStatus() async {
    bool status = await AnimeStorageService.isFavorite(widget.url);
    if (mounted) {
      setState(() {
        _isFavorited = status;
      });
    }
  }

  // 新增：切换收藏状态
  void _toggleFavorite() async {
    if (_detail == null) return;

    if (_isFavorited) {
      // 取消收藏
      await AnimeStorageService.removeFavorite(widget.url);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("已取消收藏"), duration: Duration(seconds: 1)),
        );
      }
    } else {
      // 添加收藏
      await AnimeStorageService.addFavorite(AnimeItem(
        title: _detail!.title,
        imageUrl: _detail!.imageUrl, // 这是从新fetchAnimeDetail中获取的图片
        url: widget.url,
        note: "", // 详情页一般没有note，留空即可
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("已加入收藏"), duration: Duration(seconds: 1)),
        );
      }
    }

    // 更新UI
    setState(() {
      _isFavorited = !_isFavorited;
    });
  }

  @override
  void initState() {
    super.initState();
    _checkFavoriteStatus(); // 检查收藏状态
    _loadDetail();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestFirstSourceFocus();
    });
  }

  @override
  void dispose() {
    // 退出页面时保存历史记录
    _saveHistory();

    _videoController?.dispose();
    _controlHideTimer?.cancel();
    _speedCheckTimer?.cancel(); // 取消速度检查定时器
    _seekDebounceTimer?.cancel(); // 新增：销毁防抖计时器
    _currentEpisodeNode.dispose();
    _firstSourceNode.dispose();
    _playerFocusNode.dispose(); // 销毁播放器焦点节点
    _favoriteBtnNode.dispose(); // 销毁收藏按钮焦点
    super.dispose();
  }

  void _requestFirstSourceFocus() {
    if (_detail != null && _detail!.playSources.isNotEmpty && _firstSourceNode.canRequestFocus) {
      _firstSourceNode.requestFocus();
    }
  }

  _loadDetail() async {
    try {
      var data = await AnimeApiService.fetchAnimeDetail(widget.url);
      if (!mounted) return;

      setState(() {
        _detail = data;
        _isLoading = false;
      });

      // --- 修改开始：统一处理历史进度恢复逻辑 ---

      // 1. 定义变量存储我们要恢复的目标信息
      int targetSourceIndex = 0;
      String targetEpName = "";
      int startSeconds = 0;
      bool shouldResume = false; // 标记是否需要恢复播放

      // 2. 优先检查：是否是由外部(历史记录页)直接传入的进度信息
      if (widget.initialPlaybackInfo != null) {
        targetSourceIndex = widget.initialPlaybackInfo!['sourceIndex'] ?? 0;
        targetEpName = widget.initialPlaybackInfo!['episodeName'] ?? "";
        startSeconds = widget.initialPlaybackInfo!['positionSeconds'] ?? 0;
        shouldResume = true;
      }
      // 3. 次要检查：如果外部没传，我们自己去数据库查一下有没有历史记录
      else {
        AnimeItem? historyItem = await AnimeStorageService.getHistoryItem(widget.url);
        if (historyItem != null && historyItem.playbackInfo != null) {
          targetSourceIndex = historyItem.playbackInfo!['sourceIndex'] ?? 0;
          targetEpName = historyItem.playbackInfo!['episodeName'] ?? "";
          startSeconds = historyItem.playbackInfo!['positionSeconds'] ?? 0;
          shouldResume = true;

          // 可选：给用户一个提示，告诉他正在自动恢复进度
          // if (mounted && startSeconds > 10) { // 大于10秒才提示
          //   ScaffoldMessenger.of(context).showSnackBar(
          //       SnackBar(
          //         content: Text("已为您恢复上次播放进度：$targetEpName"),
          //         duration: const Duration(seconds: 2),
          //         backgroundColor: Colors.orange,
          //       )
          //   );
          // }
        }
      }

      // 4. 如果确定有源数据，开始匹配并播放
      if (shouldResume && data.playSources.isNotEmpty) {
        // 边界检查：防止源索引越界（比如网站源变少了）
        if (targetSourceIndex >= data.playSources.length) targetSourceIndex = 0;

        // 设置UI选中的Tab
        setState(() {
          _selectedSourceIndex = targetSourceIndex;
        });

        // 在该源下查找对应的集数
        var episodes = data.playSources[targetSourceIndex].episodes;
        Episode? targetEp;
        try {
          targetEp = episodes.firstWhere((e) => e.name == targetEpName);
        } catch (_) {
          // 如果名字匹配不上（可能集数改名了），这里可以选择默认播第一集，或者不处理
          // 这里为了稳健，如果找不到对应集数，就不自动播放了，走下面的默认逻辑
        }

        if (targetEp != null) {
          // 触发播放，并传入初始跳转时间
          _handleEpisodeTap(targetEp, targetSourceIndex, startPosition: Duration(seconds: startSeconds));

          // 恢复焦点到播放器
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted && _playerFocusNode.canRequestFocus) {
              _playerFocusNode.requestFocus();
            }
          });
          return; // 成功恢复，直接返回，不再执行后续默认逻辑
        }
      }
      // --- 修改结束 ---

      // 默认逻辑：如果上面没触发恢复（或者没记录），则默认播放第一个源第一集
      if (data.playSources.isNotEmpty && data.playSources[0].episodes.isNotEmpty) {
        _handleEpisodeTap(data.playSources[0].episodes[0], 0);
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            if (_currentEpisodeNode.canRequestFocus) {
              _currentEpisodeNode.requestFocus();
            }
            _requestFirstSourceFocus();
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      print("加载详情出错: $e");
    }
  }


  // 修改：增加 startPosition 参数用于跳转
  _handleEpisodeTap(Episode ep, int sourceIndex, {Duration? startPosition}) async {
    // 只有当 播放源不同 或 集数不同 时才重新加载
    if (_currentEpisodeName == ep.name && _currentSourceIndex == sourceIndex && _videoController != null && startPosition == null) return;

    setState(() {
      _isUrlLoading = true;
      _currentEpisodeName = ep.name;
      _currentSourceIndex = sourceIndex; // 记录当前播放源索引
      _isVideoBuffering = true;
      _bufferSpeed = 0.0; // 重置速度
    });

    try {
      String realUrl = await AnimeApiService.getRealVideoUrl(ep.url);
      if (_videoController != null) {
        await _videoController!.dispose();
      }

      _videoController = VideoPlayerController.networkUrl(Uri.parse(realUrl));
      await _videoController!.initialize();

      // 如果有跳转要求
      if (startPosition != null && startPosition > Duration.zero) {
        await _videoController!.seekTo(startPosition);
      }

      // 开始监听缓冲和速度
      _listenToVideoBuffering();

      setState(() {
        _isUrlLoading = false;
      });

      _videoController!.play();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUrlLoading = false;
          _isVideoBuffering = false;
          _bufferSpeed = 0.0;
        });
      }
    }
  }

  void _resetControlTimer() {
    _controlHideTimer?.cancel();
    setState(() => _showPlayerControls = true);
    _controlHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showPlayerControls = false);
    });
  }

  void _togglePlayPause() {
    if (_videoController?.value.isInitialized == true) {
      if (_videoController!.value.isPlaying) {
        _videoController!.pause();
      } else {
        _videoController!.play();
      }
      setState(() {});
      _resetControlTimer();
    }
  }

  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
    });
    if (_isFullScreen) {
      _resetControlTimer();
    } else {
      // 退出全屏时：将焦点设置到播放器
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted && _playerFocusNode.canRequestFocus) {
            _playerFocusNode.requestFocus();
          }
        });
      });
    }
  }

  // 修改：构建加载/缓冲提示UI（显示下载速率）
  Widget _buildLoadingIndicator() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 加载动画
          const CircularProgressIndicator(
            color: Colors.orange,
            strokeWidth: 3,
          ),
          const SizedBox(height: 16),
          // 状态文字
          Text(
            _isUrlLoading ? "正在加载视频资源..." : "视频缓冲中",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              shadows: [Shadow(color: Colors.black, blurRadius: 5)],
            ),
          ),
          const SizedBox(height: 8),
          // 显示下载速率
          if (!_isUrlLoading && _bufferSpeed > 0)
            Text(
              _formatSpeed(_bufferSpeed),
              style: const TextStyle(
                color: Colors.orange,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                shadows: [Shadow(color: Colors.black, blurRadius: 5)],
              ),
            ),
          // 如果没有速度（刚开始加载或网络极慢），显示提示
          if (!_isUrlLoading && _bufferSpeed <= 0)
            const Text(
              "连接中...",
              style: TextStyle(
                color: Colors.white54,
                fontSize: 14,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isFullScreen,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isFullScreen) {
          _toggleFullScreen();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F1116),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _isFullScreen
            ? _buildFullScreenPlayer()
            : Row(
          children: [
            Expanded(flex: 7, child: _buildLeftContent()),
            Expanded(flex: 3, child: _buildRightSideBar()),
          ],
        ),
      ),
    );
  }

  Widget _buildFullScreenPlayer() {
    return Focus(
      autofocus: true,
      onKeyEvent: (FocusNode node, KeyEvent event) {
        // 1. 处理快进/快退：允许 KeyDownEvent (按下) 和 KeyRepeatEvent (长按重复)
        // 只要不是 KeyUpEvent (抬起)，都进行处理
        if (event is! KeyUpEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _handleKeySeek(false);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _handleKeySeek(true);
            //print("按了右键"); // 现在长按这里会一直打印了
            return KeyEventResult.handled;
          }
        }
        // 2. 处理确认/暂停键：通常只需要响应 KeyDownEvent (按下一次响应一次)
        // 如果这里也响应 KeyRepeatEvent，长按确认键会导致视频疯狂 播放/暂停/播放/暂停
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.gameButtonA) {
            if (!_showPlayerControls) {
              _resetControlTimer();
            } else {
              _togglePlayPause();
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: FocusableWidget(
        onTap: () {
          if (!_showPlayerControls) {
            _resetControlTimer();
          } else {
            _togglePlayPause();
          }
        },
        builder: (context, focused) {
          return Container(
            color: Colors.black,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_videoController?.value.isInitialized == true)
                  Center(
                    child: AspectRatio(
                      aspectRatio: _videoController!.value.aspectRatio,
                      child: VideoPlayer(_videoController!),
                    ),
                  ),
                // 显示加载/缓冲UI
                if (_isUrlLoading || (_isVideoBuffering && !_videoController!.value.isPlaying))
                  _buildLoadingIndicator(),
                if (_showPlayerControls)
                  _buildPlayerOverlay(isFull: true),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLeftContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 核心修改：给播放器绑定专属焦点节点
          FocusableWidget(
            focusNode: _playerFocusNode,
            onTap: () {
              _toggleFullScreen();
            },
            builder: (context, focused) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: focused ? Colors.orange : Colors.transparent,
                    width: 4,
                  ),
                  boxShadow: focused
                      ? [BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 20)]
                      : [],
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
                          if (_videoController?.value.isInitialized == true)
                            VideoPlayer(_videoController!),
                          // 小窗口也显示加载/缓冲UI
                          if ((_isUrlLoading || (_isVideoBuffering && !_videoController!.value.isPlaying)) && !_isFullScreen)
                            _buildLoadingIndicator(),
                          if (focused && !_isUrlLoading)
                            Container(
                              color: Colors.black.withOpacity(0.5),
                              child: const Icon(Icons.fullscreen, color: Colors.white, size: 60),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 30),

          // --- 修改：标题和收藏按钮 ---
          Row(
            children: [
              Expanded(
                child: Text(
                  _detail?.title ?? "",
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 20),
              // 收藏按钮
              FocusableWidget(
                focusNode: _favoriteBtnNode,
                onTap: _toggleFavorite,
                builder: (context, focused) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: focused ? Colors.white : (_isFavorited ? Colors.orange : Colors.white10),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: focused ? Colors.orange : Colors.transparent, width: 2),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isFavorited ? Icons.favorite : Icons.favorite_border,
                          color: focused ? Colors.black : Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isFavorited ? "取消收藏" : "收藏",
                          style: TextStyle(
                            color: focused ? Colors.black : Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 15),
          Row(
            children: [
              Text("正在播放：$_currentEpisodeName", style: const TextStyle(color: Colors.orange, fontSize: 16)),
              const SizedBox(width: 20),
              Text("更新：${_detail?.updateTime ?? ""}", style: const TextStyle(color: Colors.white54, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 30),
          const Divider(color: Colors.white10),
          const Text("内容简介", style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          Text(
            _detail?.introduction ?? "",
            style: const TextStyle(fontSize: 16, color: Colors.white70, height: 1.8),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerOverlay({required bool isFull}) {
    // 获取当前真实进度
    final realPos = _videoController?.value.position ?? Duration.zero;
    // 如果正在按键调整（_targetSeekPosition 不为空），优先显示虚拟进度
    final displayPos = _targetSeekPosition ?? realPos;

    final totalDuration = _videoController?.value.duration ?? Duration.zero;

    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withOpacity(0.7), Colors.transparent, Colors.black.withOpacity(0.7)],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  if (isFull) IconButton(onPressed: _toggleFullScreen, icon: const Icon(Icons.arrow_back, color: Colors.white)),
                  Text(_currentEpisodeName, style: const TextStyle(color: Colors.white, fontSize: 18)),

                  // 新增：如果正在快进快退，在顶部中间显示醒目的时间提示
                  if (_isSeekingUI)
                    Expanded(
                      child: Center(
                        child: Text(
                          "${_formatDuration(displayPos)} / ${_formatDuration(totalDuration)}",
                          style: const TextStyle(color: Colors.orange, fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Column(
              children: [
                // 注意：VideoProgressIndicator 绑定的是 controller，它只能显示真实进度，无法显示虚拟进度。
                // 为了让长按时进度条也能动，通常建议替换为 LinearProgressIndicator 或 Slider。
                // 但为了最小化改动，我们这里可以暂时保留 VideoProgressIndicator，
                // 或者用 Stack 覆盖一个显示虚拟进度的进度条。

                // 这里我们做一个简单替换：当正在拖动时，显示一个普通的 LinearProgressIndicator
                _isSeekingUI
                    ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10), // 对齐 VideoProgressIndicator 默认padding
                  child: LinearProgressIndicator(
                    value: totalDuration.inMilliseconds > 0
                        ? displayPos.inMilliseconds / totalDuration.inMilliseconds
                        : 0.0,
                    backgroundColor: Colors.grey,
                    color: Colors.orange,
                    minHeight: 5, // 保持高度一致
                  ),
                )
                    : VideoProgressIndicator(
                  _videoController!,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(playedColor: Colors.orange),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(_videoController!.value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                        onPressed: _togglePlayPause,
                      ),
                      // 修改这里：使用 displayPos 显示时间
                      Text(
                        "${_formatDuration(displayPos)} / ${_formatDuration(totalDuration)}",
                        style: TextStyle(
                            color: _isSeekingUI ? Colors.orange : Colors.white,
                            fontSize: 14
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(isFull ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white),
                        onPressed: _toggleFullScreen,
                      ),
                    ],
                  ),
                )
              ],
            ),
          ],
        ),
      ),
    );
  }


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
          SizedBox(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 15),
              itemCount: _detail?.playSources.length ?? 0,
              itemBuilder: (context, index) {
                bool isSelected = _selectedSourceIndex == index;
                return FocusableWidget(
                  focusNode: index == 0 ? _firstSourceNode : null,
                  onTap: () => setState(() => _selectedSourceIndex = index),
                  builder: (context, focused) => Container(
                    alignment: Alignment.center,
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    decoration: BoxDecoration(
                      color: focused ? Colors.orange : (isSelected ? Colors.orange.withOpacity(0.2) : Colors.white10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_detail!.playSources[index].sourceName, style: TextStyle(color: focused ? Colors.black : Colors.white)),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(20),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.5,
              ),
              itemCount: _detail?.playSources[_selectedSourceIndex].episodes.length ?? 0,
              itemBuilder: (context, index) {
                var ep = _detail!.playSources[_selectedSourceIndex].episodes[index];
                // 修改：同时判断 播放源索引 和 集数名称
                bool isPlaying = _currentSourceIndex == _selectedSourceIndex && _currentEpisodeName == ep.name;
                return FocusableWidget(
                  onTap: () => _handleEpisodeTap(ep, _selectedSourceIndex), // 传递当前选中的播放源索引
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