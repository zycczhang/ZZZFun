import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'anime_nav_widgets.dart';
import 'anime_detail_page.dart';
import 'web_server_service.dart';
import 'dart:async';
import 'models/anime_models.dart';
import 'controllers/home_controller.dart';
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
              initialPlaybackInfo: anime.playbackInfo,
            ),
          ),
        ).then((_) {
          if (onPageReturn != null) onPageReturn!();
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
                  // 1. 移除 decoration 中的 image 属性
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: focused ? Border.all(color: Colors.orange, width: 3) : null,
                    color: Colors.black, // 设置背景色防止透明闪烁
                  ),
                  // 2. 启用裁剪，确保子图片圆角显示
                  clipBehavior: Clip.antiAlias,
                  // 3. 使用 Stack/Image.network 替代 DecorationImage
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: anime.imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(color: Colors.grey[900]),
                        errorWidget: (context, url, error) => const Icon(Icons.error),
                        // 关键：TV端建议设置较小的内存缓存限制
                        memCacheWidth: 300,
                        memCacheHeight: 420,
                      ),
                      // 4. 将原有的 note 标签移到 Stack 中，保持在图片上方
                      if (anime.note.isNotEmpty)
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(anime.note, style: const TextStyle(fontSize: 10, color: Colors.orange)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(anime.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
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
  int _selectedNavIndex = 2; // 默认选中中间的“首页”图标
  late HomeController _homeController;
  bool _isPrivateUnlocked = false;

  void _unlockPrivateMode() {
    setState(() {
      _isPrivateUnlocked = true;
    });
    // 可选：给用户一个反馈
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("绅士领域已开启"),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.orange,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _homeController = HomeController();
    _homeController.init();
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
            // --- 关键修改点：使用 IndexedStack 替代原来的 switch-case ---
            //IndexedStack 会在启动时立即初始化所有子页面（搜索、个人中心、设置）。
            //全部加载完成后效果还不错，但是内存占用会变大，初始加载时间会边长，但懒加载的话切个界面就转半天也不舒服
            child: IndexedStack(
              index: _selectedNavIndex,
              children: [
                SearchPage(onUnlockPrivate: _unlockPrivateMode), // Index 0
                const PersonalCenterPage(),                     // Index 1
                _buildNestedHomeView(),                        // Index 2: 首页
                const SettingsPage(),                          // Index 3
              ],
            ),
          ),
        ],
      ),
    );
  }
  // 修改 _buildNestedHomeView，添加 PageStorageKey 保持滚动位置
  Widget _buildNestedHomeView() {
    return ListenableBuilder(
      listenable: _homeController,
      builder: (context, child) {
        if (_homeController.isLoading) {
          return const Center(child: CircularProgressIndicator(color: Colors.orange));
        }
        return ListView(
          key: const PageStorageKey('home_scroll_view'),
          cacheExtent: 1000,
          padding: const EdgeInsets.symmetric(vertical: 30),
          children: [
            _buildBannerSection(),
            const SizedBox(height: 10),

            // --- 关键修改：标题与星期切换在同一行 ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 装饰条 + 标题
                  Container(
                    width: 5,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 2. 标题文字
                  const Text(
                      "新番表",
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      )
                  ),

                  // 星期切换按钮（占据剩余所有空间）
                  Expanded(
                    child: _buildWeekTabs(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 25), // 增加一点和网格的间距
            _buildWeeklyGridView(),
          ],
        );
      },
    );
  }
  // 板块1：轮播图 (Banner)
  Widget _buildBannerSection() {
    if (_homeController.banners.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 310, // 稍微加高，更具视觉冲击力
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        //padding: const EdgeInsets.symmetric(horizontal: 40), // 与网格对齐
        itemCount: _homeController.banners.length,
        cacheExtent: 1000,
        itemBuilder: (context, index) {
          final item = _homeController.banners[index];
          return FocusableWidget(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AnimeDetailPage(url: item.url)),
            ),
            builder: (context, focused) {
              return AnimatedScale(
                scale: focused ? 1.03 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 620, // 宽屏比例更像电影海报
                  //动态设置第一个和最后一个元素的 margin ---
                  margin: EdgeInsets.only(
                    left: index == 0 ? 40 : 0, // 只有第一项左边留 40
                    right: index == _homeController.banners.length - 1 ? 40 : 25, // 最后一项右边留 40，其他留 25
                    top: 10,
                    bottom: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    // 焦点状态下的发光阴影
                    boxShadow: focused ? [
                      BoxShadow(
                        color: Colors.orange.withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 5,
                      )
                    ] : [],
                  ),
                  child: Stack(
                    children: [
                      // 1. 底层图片
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: CachedNetworkImage(
                            imageUrl: item.imageUrl,
                            fit: BoxFit.cover,
                            // 针对 TV 端的性能优化
                            memCacheWidth: 1000, // 限制解码后的内存占用
                            maxWidthDiskCache: 1200, // 限制磁盘缓存的分辨率
                            fadeOutDuration: const Duration(milliseconds: 300),
                            fadeInDuration: const Duration(milliseconds: 500),
                            // 加载时的占位图
                            placeholder: (context, url) => Container(
                              color: const Color(0xFF1E1E1E),
                              child: const Center(
                                child: CircularProgressIndicator(color: Colors.orange, strokeWidth: 2),
                              ),
                            ),
                            // 错误时的占位图
                            errorWidget: (context, url, error) => Container(
                              color: const Color(0xFF1E1E1E),
                              child: const Icon(Icons.broken_image, color: Colors.white24, size: 50),
                            ),
                          ),
                        ),
                      ),
                      // 2. 增强版遮罩：三段渐变（底部最黑，中间半透，顶部全透）
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              stops: const [0.0, 0.4, 0.8],
                              colors: [
                                Colors.black.withOpacity(0.9),
                                Colors.black.withOpacity(0.3),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                      // 3. 内容层
                      Positioned(
                        left: 25,
                        bottom: 25,
                        right: 25,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 顶部的一个小胶囊标签（用于显示备注）
                            if (item.note.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: Colors.orange,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  item.note,
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            Text(
                              item.title,
                              style: const TextStyle(
                                fontSize: 30, // 标题加大
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 1.2,
                                shadows: [Shadow(blurRadius: 10, color: Colors.black, offset: Offset(2, 2))],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      // 4. 焦点边框 (更显眼的橙色边框)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: focused ? Colors.orange : Colors.white.withOpacity(0.1),
                              width: focused ? 4 : 1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
  // 板块2：星期切换 Tab
  Widget _buildWeekTabs() {
    if (_homeController.weeklyAnime.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 45,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 35),
        itemCount: _homeController.weeklyAnime.length,
        itemBuilder: (context, index) {
          bool isSelected = _homeController.selectedWeekIndex == index;
          return FocusableWidget(
            onTap: () => _homeController.changeWeek(index),
            builder: (context, focused) {
              return Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 25),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: focused ? Colors.white : (isSelected ? Colors.orange : Colors.white10),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Text(
                  _homeController.weeklyAnime[index].day,
                  style: TextStyle(
                    color: focused ? Colors.black : Colors.white,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
  // 板块3：新番列表网格
  Widget _buildWeeklyGridView() {
    if (_homeController.weeklyAnime.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      // 使用 IndexedStack 保持每一页的状态
      child: IndexedStack(
        index: _homeController.selectedWeekIndex,
        children: _homeController.weeklyAnime.map((weekData) {
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              crossAxisSpacing: 20,
              mainAxisSpacing: 30,
              childAspectRatio: 0.7,
            ),
            itemCount: weekData.items.length,
            // 关键：给每一个 GridView 加上唯一的 Key，帮助 Flutter 识别
            key: PageStorageKey('week_${weekData.day}'),
            itemBuilder: (context, index) => VideoCard(anime: weekData.items[index]),
          );
        }).toList(),
      ),
    );
  }

}


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
