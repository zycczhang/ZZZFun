import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'anime_nav_widgets.dart';
import 'anime_detail_page.dart';
import 'web_server_service.dart';
import 'dart:async';
import 'models/anime_models.dart';
import 'services/anime_api_service.dart';
import 'services/anime_storage_service.dart';
// VideoCard 类 - 包含AI的修改（传递播放进度、样式优化）
class VideoCard extends StatelessWidget {
  final AnimeItem anime;
  final VoidCallback? onPageReturn;

  const VideoCard({super.key, required this.anime, this.onPageReturn});

  @override
  Widget build(BuildContext context) {
    return FocusableWidget(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AnimeDetailPage(
              url: anime.url,
              // 关键修改：传递历史进度信息
              initialPlaybackInfo: anime.playbackInfo,
            ),
          ),
        ).then((_) {
          if (onPageReturn != null) {
            onPageReturn!();
          }
        });
      },
      builder: (context, focused) {
        return AnimatedScale(
          scale: focused ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: focused ? Border.all(color: Colors.white, width: 3) : null,
                    image: DecorationImage(
                      image: anime.imageUrl.isNotEmpty
                          ? NetworkImage(anime.imageUrl)
                          : const NetworkImage("https://via.placeholder.com/150"),
                      fit: BoxFit.cover,
                    ),
                  ),
                  child: Stack(
                    children: [
                      if (anime.note.isNotEmpty)
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.8), // 加深背景色
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              anime.note,
                              style: const TextStyle(fontSize: 10, color: Colors.orange), // 改变颜色突出显示
                            ),
                          ),
                        )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                anime.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        );
      },
    );
  }
}

// PersonalCenterPage 类 - 完整修改版（合并收藏和历史功能）
class PersonalCenterPage extends StatefulWidget {
  const PersonalCenterPage({super.key});

  @override
  State<PersonalCenterPage> createState() => _PersonalCenterPageState();
}

class _PersonalCenterPageState extends State<PersonalCenterPage> {
  int _selectedTabIndex = 0; // 0: 收藏, 1: 历史
  final FocusNode _firstPersonalTabNode = FocusNode();

  List<AnimeItem> _items = []; // 复用列表，根据 tab 不同加载不同数据
  int _currentPage = 0;
  final int _pageSize = 20;
  bool _isLoading = true;

  StreamSubscription? _refreshSub; // 新增
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_firstPersonalTabNode.canRequestFocus) {
        _firstPersonalTabNode.requestFocus();
      }
    });
    _loadData();

    // 监听刷新事件 (当 Web 端修改收藏后)
    _refreshSub = ServerEventBus.stream.listen((event) {
      if (event == ServerEventBus.eventRefreshData) {
        // 重新加载数据
        _loadData();
      }
    });
  }

  // 加载数据：根据当前 Tab 决定加载收藏还是历史
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      List<AnimeItem> data;
      if (_selectedTabIndex == 0) {
        data = await AnimeStorageService.getFavorites();
        data = data.reversed.toList(); // 收藏也按时间倒序
      } else {
        data = await AnimeStorageService.getHistory(); // 历史本身就是最新的在最前
      }

      if (mounted) {
        setState(() {
          _items = data;
          _isLoading = false;
          // 重置页码
          if (_currentPage * _pageSize >= _items.length && _currentPage > 0) {
            _currentPage = 0;
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _refreshSub?.cancel(); // 取消监听
    _firstPersonalTabNode.dispose();
    super.dispose();
  }

  int get _totalPages {
    if (_items.isEmpty) return 1;
    return (_items.length / _pageSize).ceil();
  }

  List<AnimeItem> get _currentItems {
    if (_items.isEmpty) return [];
    int start = _currentPage * _pageSize;
    int end = start + _pageSize;
    if (end > _items.length) end = _items.length;
    if (start >= _items.length) return [];
    return _items.sublist(start, end);
  }

  void _prevPage() {
    if (_currentPage > 0) {
      setState(() => _currentPage--);
    }
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      setState(() => _currentPage++);
    }
  }

  Widget _buildTabItem(int index, String title, [FocusNode? focusNode]) {
    bool isSelected = _selectedTabIndex == index;
    return FocusableWidget(
      focusNode: focusNode,
      builder: (context, focused) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: focused
                ? Colors.white
                : (isSelected ? Colors.white24 : Colors.transparent),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            title,
            style: TextStyle(
              color: focused ? Colors.black : Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
      onTap: () {
        if (_selectedTabIndex != index) {
          setState(() {
            _selectedTabIndex = index;
            _currentPage = 0; // 切换 Tab 时重置页码
          });
          _loadData();
        }
      },
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_selectedTabIndex == 0 ? Icons.favorite_border : Icons.history, color: Colors.grey, size: 80),
            const SizedBox(height: 20),
            Text(_selectedTabIndex == 0 ? "暂无收藏内容" : "暂无播放历史", style: const TextStyle(color: Colors.grey, fontSize: 20)),
          ],
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              crossAxisSpacing: 20,
              mainAxisSpacing: 30,
              childAspectRatio: 0.7,
            ),
            itemCount: _currentItems.length,
            itemBuilder: (context, index) {
              return VideoCard(
                anime: _currentItems[index],
                onPageReturn: () => _loadData(), // 从详情页返回时刷新数据
              );
            },
          ),
        ),
        if (_totalPages > 1)
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Opacity(
                  opacity: _currentPage > 0 ? 1.0 : 0.3,
                  child: FocusableWidget(
                    onTap: _prevPage,
                    builder: (context, focused) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: focused ? Colors.white : Colors.white10,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text("上一页", style: TextStyle(color: focused ? Colors.black : Colors.white)),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    "${_currentPage + 1} / $_totalPages",
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
                Opacity(
                  opacity: _currentPage < _totalPages - 1 ? 1.0 : 0.3,
                  child: FocusableWidget(
                    onTap: _nextPage,
                    builder: (context, focused) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: focused ? Colors.white : Colors.white10,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text("下一页", style: TextStyle(color: focused ? Colors.black : Colors.white)),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 30),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildTabItem(0, "我的收藏"),
              _buildTabItem(1, "播放历史"),
            ],
          ),
        ),
        Expanded(
          child: _buildContent(),
        ),
      ],
    );
  }
}

// SearchPage 类 - 保持原有逻辑不变
class SearchPage extends StatefulWidget {
  // 1. 新增回调函数
  final VoidCallback? onUnlockPrivate;

  const SearchPage({super.key, this.onUnlockPrivate});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();

  late FocusNode _inputFocusNode;
  late FocusNode _buttonFocusNode;
  late FocusNode _modeFocusNode;

  List<AnimeItem> _searchResults = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  int _currentPage = 1;
  bool _hasNextPage = false;
  String _currentKeyword = "";
  bool _isSearchByName = true;

  @override
  void initState() {
    super.initState();
    _modeFocusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          _inputFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.gameButtonA) {
          _toggleSearchMode();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );

    _buttonFocusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _inputFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.gameButtonA) {
          _doSearch(_controller.text);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );

    _inputFocusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _buttonFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _modeFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            FocusScope.of(context).focusInDirection(TraversalDirection.down);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );

    _modeFocusNode.addListener(() { if (mounted) setState(() {}); });
    _inputFocusNode.addListener(() { if (mounted) setState(() {}); });
    _buttonFocusNode.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _controller.dispose();
    _inputFocusNode.dispose();
    _buttonFocusNode.dispose();
    _modeFocusNode.dispose();
    super.dispose();
  }

  void _doSearch(String keyword, {int page = 1}) async {
    if (keyword.isEmpty) return;

    // 2. 新增：检测暗号逻辑
    if (keyword.toLowerCase() == 'zycnb') {
      if (widget.onUnlockPrivate != null) {
        widget.onUnlockPrivate!(); // 触发解锁
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("绅士领域已开启，请前往首页查看")),
          );
        }
        // 清空输入框
        _controller.clear();
      }
      return; // 拦截搜索，不发送网络请求
    }

    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _currentKeyword = keyword;
      if (page == 1) _searchResults = [];
    });

    try {
      if (_isSearchByName) {
        SearchResult result = await AnimeApiService.searchAnime(keyword, page: page);
        setState(() {
          _searchResults = result.items;
          _hasNextPage = result.hasNextPage;
          _currentPage = page;
          _isLoading = false;
        });
      } else {
        AnimeItem? item = await AnimeApiService.getAnimeById(keyword);
        setState(() {
          if (item != null) {
            _searchResults = [item];
          } else {
            _searchResults = [];
            if(mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("未找到该ID对应的视频")));
            }
          }
          _hasNextPage = false;
          _currentPage = 1;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _searchResults = [];
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("搜索出错: $e")));
      }
    }
  }

  void _nextPage() {
    if (_hasNextPage && _isSearchByName) {
      _doSearch(_currentKeyword, page: _currentPage + 1);
    }
  }

  void _prevPage() {
    if (_currentPage > 1 && _isSearchByName) {
      _doSearch(_currentKeyword, page: _currentPage - 1);
    }
  }

  void _toggleSearchMode() {
    setState(() {
      _isSearchByName = !_isSearchByName;
      _controller.clear();
      _searchResults = [];
      _hasSearched = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(40, 50, 40, 20),
          child: FocusTraversalGroup(
            child: Row(
              children: [
                Focus(
                  focusNode: _modeFocusNode,
                  onKeyEvent: (node, event) {
                    if (event is! KeyDownEvent) return KeyEventResult.ignored;

                    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                      _inputFocusNode.requestFocus();
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.select ||
                        event.logicalKey == LogicalKeyboardKey.enter ||
                        event.logicalKey == LogicalKeyboardKey.gameButtonA) {
                      _toggleSearchMode();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: GestureDetector(
                    onTap: _toggleSearchMode,
                    child: Container(
                      width: 110,
                      margin: const EdgeInsets.only(right: 15),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      decoration: BoxDecoration(
                          color: _modeFocusNode.hasFocus ? Colors.orange : Colors.white24,
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(
                              color: _modeFocusNode.hasFocus ? Colors.white : Colors.transparent,
                              width: 2
                          )
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _isSearchByName ? "按名称" : "按ID",
                            style: TextStyle(
                              color: _modeFocusNode.hasFocus ? Colors.black : Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                              Icons.arrow_drop_down,
                              color: _modeFocusNode.hasFocus ? Colors.black : Colors.white
                          )
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(
                            color: _inputFocusNode.hasFocus ? Colors.orange : Colors.transparent,
                            width: 2
                        )
                    ),
                    child: TextField(
                      controller: _controller,
                      focusNode: _inputFocusNode,
                      style: const TextStyle(color: Colors.white),
                      textInputAction: TextInputAction.search,
                      autofocus: false,
                      readOnly: false,
                      keyboardType: _isSearchByName ? TextInputType.text : TextInputType.number,
                      decoration: InputDecoration(
                        hintText: _isSearchByName ? "输入关键字..." : "输入视频ID (如: 318177)",
                        hintStyle: const TextStyle(color: Colors.white30),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                        icon: const Padding(
                          padding: EdgeInsets.only(left: 15),
                          child: Icon(Icons.search, color: Colors.white54),
                        ),
                      ),
                      onSubmitted: (value) => _doSearch(value),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                GestureDetector(
                  onTap: () => _doSearch(_controller.text),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 12),
                    decoration: BoxDecoration(
                      color: _buttonFocusNode.hasFocus ? Colors.orange : Colors.white24,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Focus(
                      focusNode: _buttonFocusNode,
                      child: Text(
                        "搜索",
                        style: TextStyle(
                            color: _buttonFocusNode.hasFocus ? Colors.black : Colors.white,
                            fontWeight: FontWeight.bold
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : !_hasSearched
              ? Center(child: Text(_isSearchByName ? "请输入关键字开始搜索" : "请输入ID直接跳转", style: const TextStyle(color: Colors.white30)))
              : _searchResults.isEmpty
              ? const Center(child: Text("未找到相关内容", style: TextStyle(color: Colors.white54)))
              : Column(
            children: [
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    crossAxisSpacing: 20,
                    mainAxisSpacing: 30,
                    childAspectRatio: 0.7,
                  ),
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    return VideoCard(anime: _searchResults[index]);
                  },
                ),
              ),
              if (_isSearchByName && (_currentPage > 1 || _hasNextPage))
                Container(
                  height: 60,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_currentPage > 1)
                        FocusableWidget(
                          onTap: _prevPage,
                          builder: (context, focused) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            margin: const EdgeInsets.only(right: 20),
                            decoration: BoxDecoration(
                              color: focused ? Colors.white : Colors.white10,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text("上一页", style: TextStyle(color: focused ? Colors.black : Colors.white)),
                          ),
                        ),
                      Text("第 $_currentPage 页", style: const TextStyle(color: Colors.white54)),
                      if (_hasNextPage)
                        FocusableWidget(
                          onTap: _nextPage,
                          builder: (context, focused) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            margin: const EdgeInsets.only(left: 20),
                            decoration: BoxDecoration(
                              color: focused ? Colors.white : Colors.white10,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text("下一页", style: TextStyle(color: focused ? Colors.black : Colors.white)),
                          ),
                        ),
                    ],
                  ),
                )
            ],
          ),
        ),
      ],
    );
  }
}

// TvHomePage 类 - 保持原有逻辑不变
class TvHomePage extends StatefulWidget {
  const TvHomePage({super.key});
  @override
  State<TvHomePage> createState() => _TvHomePageState();
}

class _TvHomePageState extends State<TvHomePage> {
  int _selectedTopIndex = 0; // 0:动画, 1:综艺, 2:电影, 3:电视剧 4.私密
  int _selectedNavIndex = 2; // 默认首页
  // 1. 新增：私密模式解锁状态
  bool _isPrivateUnlocked = false;
  // 星期栏相关 (仅 Tab 0 使用)
  int _selectedWeekIndex = 100; // 0-6 代表周一到周日, 100 代表动画库
  List<WeeklyData> _weeklyAnimeData = [];
  bool _isWeekLoading = true;

  // 通用分类库数据 (用于 动画库/综艺/电影/电视剧)
  List<AnimeItem> _libraryItems = [];
  int _libraryPage = 1;
  bool _libraryHasNext = false;
  bool _isLibraryLoading = false;

  // 常量定义
  static const int _animeWeekLibId = 100; // 动画页中的"库"按钮ID

  final FocusNode _firstTabNode = FocusNode();

  // 新增：事件订阅
  StreamSubscription? _serverEventSub;
  @override
  void initState() {
    super.initState();
    _fetchWeeklyData();
    // 初始加载动画库数据 (默认 Anime ID 4)
    _fetchLibraryData(typeId: 4, page: 1);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_selectedNavIndex == 2 && _firstTabNode.canRequestFocus) {
        _firstTabNode.requestFocus();
      }


    });

    // 监听服务器事件
    _serverEventSub = ServerEventBus.stream.listen((event) {
      if (event.startsWith(ServerEventBus.eventPlayUrl)) {
        String url = event.substring(ServerEventBus.eventPlayUrl.length);
        _handleRemotePlay(url);
      }
    });

  }

  @override
  void dispose() {
    _serverEventSub?.cancel(); // 记得取消监听
    _firstTabNode.dispose();
    super.dispose();
  }

  void _handleRemotePlay(String url) {
    if (!mounted) return;
    // 使用 Navigator 跳转
    // 注意：如果当前已经在播放页，可能需要先 pop，这里简单处理直接 push
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AnimeDetailPage(url: url),
      ),
    );
  }

  void _unlockPrivateMode() {
    setState(() {
      _isPrivateUnlocked = true;
      // 可选：解锁后直接跳转回首页看效果
      // _selectedNavIndex = 2;
      // _selectedTopIndex = 4; // 直接选中私密Tab
    });
    // 切换到私密Tab后，立即加载数据
    // _fetchLibraryData(typeId: 5, page: 1);
  }

  // 获取 Tab 对应的 TypeId
  int _getTypeIdForTab(int tabIndex) {
    switch (tabIndex) {
      case 0: return 4; // 动画
      case 1: return 3; // 综艺 (3)
      case 2: return 1; // 电影 (通常是 1)
      case 3: return 2; // 电视剧 (2)
      case 4: return 5; // 私密专区
      default: return 4;
    }
  }

  // 切换顶部 Tab
  void _onTopTabChanged(int index) {
    if (_selectedTopIndex == index) return;

    setState(() {
      _selectedTopIndex = index;
      // 切换 Tab 时重置库数据
      _libraryItems = [];
      _libraryPage = 1;
      _isLibraryLoading = true;
    });

    // 如果不是动画Tab(0)，或者 是动画Tab且当前选中的是"库"(100)，则加载数据
    if (index != 0 || (index == 0 && _selectedWeekIndex == _animeWeekLibId)) {
      _fetchLibraryData(typeId: _getTypeIdForTab(index), page: 1);
    }
  }

  // 获取首页周更表
  Future<void> _fetchWeeklyData() async {
    setState(() => _isWeekLoading = true);
    try {
      var data = await AnimeApiService.fetchAnimeData();
      setState(() {
        _weeklyAnimeData = data;
        _isWeekLoading = false;
      });
    } catch (e) {
      print("周更表异常: $e");
      if(mounted) setState(() => _isWeekLoading = false);
    }
  }

  // 获取分类库数据 (通用)
  Future<void> _fetchLibraryData({required int typeId, int page = 1}) async {
    setState(() {
      _isLibraryLoading = true;
      _libraryItems = [];
    });

    try {
      var result = await AnimeApiService.fetchCategoryData(typeId, page: page);
      if (mounted) {
        setState(() {
          _libraryItems = result.items;
          _libraryHasNext = result.hasNextPage;
          _libraryPage = page;
          _isLibraryLoading = false;
        });
      }
    } catch (e) {
      print("分类库异常: $e");
      if (mounted) setState(() => _isLibraryLoading = false);
    }
  }

  // 翻页逻辑
  void _changeLibraryPage(int newPage) {
    int typeId = _getTypeIdForTab(_selectedTopIndex);
    _fetchLibraryData(typeId: typeId, page: newPage);
  }

  // 构建星期栏（包含“动画库”按钮）- 仅用于 Tab 0
  Widget _buildWeekBar() {
    List<Widget> weekButtons = List.generate(_weeklyAnimeData.length, (index) {
      bool isSelected = _selectedWeekIndex == index;
      return FocusableWidget(
        onTap: () => setState(() => _selectedWeekIndex = index),
        builder: (context, focused) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: focused ? Colors.white : (isSelected ? Colors.blueAccent : Colors.white10),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _weeklyAnimeData[index].day,
              style: TextStyle(color: focused ? Colors.black : Colors.white, fontSize: 13),
            ),
          );
        },
      );
    });

    bool isLibSelected = _selectedWeekIndex == _animeWeekLibId;
    weekButtons.add(
      FocusableWidget(
        onTap: () {
          setState(() {
            _selectedWeekIndex = _animeWeekLibId;
          });
          _fetchLibraryData(typeId: 4, page: 1); // 动画库 ID 4
        },
        builder: (context, focused) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: focused ? Colors.white : (isLibSelected ? Colors.orange : Colors.white10),
              borderRadius: BorderRadius.circular(4),
              border: isLibSelected ? Border.all(color: Colors.orange) : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.video_library, size: 14, color: focused ? Colors.black : Colors.white),
                const SizedBox(width: 4),
                Text(
                  "动画库",
                  style: TextStyle(color: focused ? Colors.black : Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          );
        },
      ),
    );
    return Container(
      height: 40,
      margin: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: weekButtons,
      ),
    );
  }

  // 通用的网格+分页视图
  Widget _buildLibraryView() {
    if (_isLibraryLoading && _libraryItems.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_libraryItems.isEmpty) {
      return const Center(child: Text("暂无数据——更换节点试试", style: TextStyle(color: Colors.white54)));
    }
    return Column(
      children: [
        // 列表区域
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              crossAxisSpacing: 20,
              mainAxisSpacing: 30,
              childAspectRatio: 0.7,
            ),
            itemCount: _libraryItems.length,
            itemBuilder: (context, index) => VideoCard(anime: _libraryItems[index]),
          ),
        ),
        // 分页区域
        Container(
          height: 60,
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 上一页
              if (_libraryPage > 1)
                FocusableWidget(
                  onTap: () => _changeLibraryPage(_libraryPage - 1),
                  builder: (context, focused) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    margin: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(
                      color: focused ? Colors.white : Colors.white10,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text("上一页", style: TextStyle(color: focused ? Colors.black : Colors.white)),
                  ),
                ),

              Text("第 $_libraryPage 页", style: const TextStyle(color: Colors.white54)),

              // 下一页
              if (_libraryHasNext)
                FocusableWidget(
                  onTap: () => _changeLibraryPage(_libraryPage + 1),
                  builder: (context, focused) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    margin: const EdgeInsets.only(left: 20),
                    decoration: BoxDecoration(
                      color: focused ? Colors.white : Colors.white10,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text("下一页", style: TextStyle(color: focused ? Colors.black : Colors.white)),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // 构建内容区域
  Widget _buildHomeContent() {
    // 逻辑：
    // 1. 如果是 Tab 0 (动画)
    if (_selectedTopIndex == 0) {
      // 如果选中了动画库按钮，显示通用库视图
      if (_selectedWeekIndex == _animeWeekLibId) {
        return _buildLibraryView();
      }
      // 否则显示周更表内容
      if (_selectedWeekIndex >= _weeklyAnimeData.length) {
        return const SizedBox();
      }
      var currentList = _weeklyAnimeData[_selectedWeekIndex].items;
      return GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          crossAxisSpacing: 20,
          mainAxisSpacing: 30,
          childAspectRatio: 0.7,
        ),
        itemCount: currentList.length,
        itemBuilder: (context, index) => VideoCard(anime: currentList[index]),
      );
    }
    // 2. 如果是 Tab 1 (综艺), 2 (电影), 3 (电视剧), 4 (私密)
    else {
      // 直接显示通用库视图
      return _buildLibraryView();
    }
  }

  Widget _buildOtherPage(String title) {
    return Center(
      child: Text(
        "$title 页面  没什么要设置的",
        style: const TextStyle(fontSize: 24, color: Colors.grey),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          SideNavigation(
            selectedNavIndex: _selectedNavIndex,
            onNavSelected: (index) => setState(() => _selectedNavIndex = index),
          ),
          Expanded(
            child: _selectedNavIndex == 2 // 首页
                ? Column(
              children: [
                TopHeader(
                  selectedIndex: _selectedTopIndex,
                  onTabChanged: _onTopTabChanged,
                  firstTabNode: _firstTabNode,
                  showPrivate: _isPrivateUnlocked,
                ),
                if (_selectedTopIndex == 0 && !_isWeekLoading)
                  _buildWeekBar(),
                Expanded(
                  child: (_selectedTopIndex == 0 && _isWeekLoading)
                      ? const Center(child: CircularProgressIndicator())
                      : _buildHomeContent(),
                ),
              ],
            )
                : _selectedNavIndex == 0
                ? SearchPage(onUnlockPrivate: _unlockPrivateMode)
                : _selectedNavIndex == 1
                ? const PersonalCenterPage()
            // 修改这里：第4个选项（索引3）显示设置页面
                : const SettingsPage(),
          ),
        ],
      ),
    );
  }
}


// --- 新增：设置页面 (线路切换) ---
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}
class _SettingsPageState extends State<SettingsPage> {
  List<RouteItem> _routes = [];
  bool _isLoading = true;
  String _currentUrl = "";
  final FocusNode _retryBtnNode = FocusNode();
  @override
  void initState() {
    super.initState();
    _currentUrl = AnimeApiService.baseUrl;
    _loadRoutes();
  }
  @override
  void dispose() {
    _retryBtnNode.dispose();
    super.dispose();
  }
  Future<void> _loadRoutes() async {
    setState(() => _isLoading = true);
    var routes = await AnimeApiService.fetchAvailableRoutes();

    // 如果获取失败，至少保留当前正在使用的作为选项
    if (routes.isEmpty) {
      routes.add(RouteItem(name: "默认线路 (获取列表失败)", url: AnimeApiService.baseUrl));
    }
    if (mounted) {
      setState(() {
        _routes = routes;
        _isLoading = false;
      });
    }
  }
  Future<void> _changeRoute(String url) async {
    setState(() => _currentUrl = url);
    // 1. 修改内存中的 baseUrl
    AnimeApiService.baseUrl = url;
    // 2. 持久化保存
    await AnimeStorageService.setBaseUrl(url);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("已切换至: $url"),
          duration: const Duration(milliseconds: 1500),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(40, 50, 40, 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("网页线路设置", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
              Text("网页面板：${WebServerService.serverUrl}", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
              // 刷新按钮
              FocusableWidget(
                focusNode: _retryBtnNode,
                onTap: _loadRoutes,
                builder: (context, focused) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: focused ? Colors.white : Colors.white10,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.refresh, color: focused ? Colors.black : Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text("刷新线路列表", style: TextStyle(color: focused ? Colors.black : Colors.white)),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),

        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 10),
            itemCount: _routes.length,
            itemBuilder: (context, index) {
              final route = _routes[index];
              final isSelected = route.url == _currentUrl;
              return FocusableWidget(
                onTap: () => _changeRoute(route.url),
                builder: (context, focused) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                    decoration: BoxDecoration(
                      // 选中状态给一个背景色，聚焦状态给白色高亮
                      color: focused
                          ? Colors.white
                          : (isSelected ? Colors.orange.withOpacity(0.2) : Colors.white10),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? Colors.orange : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      children: [
                        // 模拟 Radio Button
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: focused
                                    ? Colors.black
                                    : (isSelected ? Colors.orange : Colors.white54),
                                width: 2
                            ),
                          ),
                          child: isSelected
                              ? Center(child: Container(width: 10, height: 10, decoration: BoxDecoration(color: focused ? Colors.black : Colors.orange, shape: BoxShape.circle)))
                              : null,
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                route.name,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: focused ? Colors.black : Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                route.url,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: focused ? Colors.black54 : Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 如果是当前选中，显示状态标签
                        if (isSelected)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text("当前使用", style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),

        Padding(
          padding: const EdgeInsets.all(40.0),
          child: Row(
            // 关键属性：让子组件两端对齐
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "提示：如果没有数据，请尝试切换其他线路。",
                style: TextStyle(color: Colors.grey),
              ),
              Text(
                "项目地址：https://github.com/zycczhang/ZycFun",
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
