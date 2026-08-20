import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'anime_nav_widgets.dart';
import 'models/anime_models.dart';
import 'models/bangumi_models.dart';
import 'services/anime_storage_service.dart';
import 'services/app_logger.dart';
import 'services/bangumi_api_service.dart';

class _CachedSearchPage {
  final List<AnimeItem> items;
  final bool hasNext;
  final bool noResults;
  final String? error;
  final int total;

  const _CachedSearchPage({
    required this.items,
    required this.hasNext,
    required this.noResults,
    required this.error,
    required this.total,
  });
}

class TvHomePage extends StatefulWidget {
  const TvHomePage({super.key});

  @override
  State<TvHomePage> createState() => _TvHomePageState();
}

class _TvHomePageState extends State<TvHomePage> {
  static const _searchPageSize = 20;
  static const _maxSearchResults = 100;
  static const _maxCachedSearchPages = 20;

  int _selectedPage = 0;
  int _selectedWeekday = DateTime.now().weekday;
  final BangumiApiService _bangumiApi = BangumiApiService();

  List<AnimeItem> _popularItems = const [];
  List<AnimeItem> _favorites = const [];
  List<AnimeItem> _history = const [];
  List<AnimeItem> _searchItems = const [];
  List<BangumiCalendarDay> _calendarDays = const [];
  bool _popularLoading = true;
  bool _calendarLoading = true;
  bool _searchLoading = false;
  bool _searchHasNext = false;
  bool _searchNoResults = false;
  String? _popularError;
  String? _calendarError;
  String? _searchError;
  String _searchQuery = '';
  int _searchPageOffset = 0;
  int _searchRequestId = 0;
  final Map<String, _CachedSearchPage> _searchPageCache =
      <String, _CachedSearchPage>{};

  @override
  void initState() {
    super.initState();
    _loadLibrary();
    _loadPopular();
    _loadCalendar();
  }

  @override
  void dispose() {
    _bangumiApi.close();
    super.dispose();
  }

  Future<void> _loadPopular() async {
    try {
      final subjects = await _bangumiApi.getCurrentSeasonPopularSubjects(
        limit: 24,
      );
      final items = subjects.map(AnimeItem.fromBangumi).toList(growable: false);
      if (items.isEmpty) {
        throw const BangumiApiException('热门番剧没有有效数据');
      }
      if (!mounted) return;
      setState(() {
        _popularItems = items;
        _popularLoading = false;
        _popularError = null;
      });
      AppLogger.info('bangumi', '热门番剧已加载: ${items.length} 部');
    } catch (error, stackTrace) {
      AppLogger.warning('bangumi', '热门番剧加载失败', error, stackTrace);
      if (mounted) {
        setState(() {
          _popularLoading = false;
          _popularError = error.toString();
        });
      }
    }
  }

  Future<void> _loadCalendar() async {
    try {
      final days = await _bangumiApi.getCalendar();
      if (!mounted) return;
      final selectedDay = days.any((day) => day.weekdayId == _selectedWeekday)
          ? _selectedWeekday
          : days.isEmpty
          ? _selectedWeekday
          : days.first.weekdayId;
      setState(() {
        _calendarDays = days;
        _selectedWeekday = selectedDay;
        _calendarLoading = false;
        _calendarError = null;
      });
      AppLogger.info('bangumi', '放送日历已加载: ${days.length} 天');
    } catch (error, stackTrace) {
      AppLogger.warning('bangumi', '放送日历加载失败', error, stackTrace);
      if (mounted) {
        setState(() {
          _calendarLoading = false;
          _calendarError = error.toString();
        });
      }
    }
  }

  Future<void> _loadLibrary() async {
    final favorites = await AnimeStorageService.getFavorites();
    final history = await AnimeStorageService.getHistory();
    if (!mounted) return;
    setState(() {
      _favorites = favorites;
      _history = history;
    });
  }

  Future<void> _searchAnime(String keyword) async {
    final query = keyword.trim();
    _searchQuery = query;
    if (query.isEmpty) {
      ++_searchRequestId;
      setState(() {
        _searchItems = const [];
        _searchLoading = false;
        _searchHasNext = false;
        _searchNoResults = false;
        _searchError = null;
      });
      return;
    }

    _searchPageOffset = 0;
    await _loadSearchPage(query, 0);
  }

  Future<void> _loadSearchPage(String query, int offset) async {
    final requestId = ++_searchRequestId;
    final cacheKey = _searchCacheKey(query, offset);
    final cachedPage = _searchPageCache.remove(cacheKey);
    if (cachedPage != null) {
      _searchPageCache[cacheKey] = cachedPage;
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        _searchItems = cachedPage.items;
        _searchLoading = false;
        _searchPageOffset = offset;
        _searchHasNext = cachedPage.hasNext;
        _searchNoResults = cachedPage.noResults;
        _searchError = cachedPage.error;
      });
      AppLogger.info('bangumi', '搜索缓存命中: "$query"，offset=$offset');
      return;
    }

    setState(() {
      _searchItems = const [];
      _searchLoading = true;
      _searchPageOffset = offset;
      _searchHasNext = false;
      _searchNoResults = false;
      _searchError = null;
    });
    try {
      final page = await _bangumiApi.searchSubjects(
        query,
        limit: _searchPageSize,
        offset: offset,
        sort: 'heat',
      );
      if (!mounted || requestId != _searchRequestId) return;
      final items = page.subjects
          .where((subject) => _matchesSearchKeyword(subject, query))
          .map(AnimeItem.fromBangumi)
          .toList(growable: false);
      final hasNext =
          page.subjects.length >= _searchPageSize &&
          offset + _searchPageSize < page.total &&
          offset + _searchPageSize < _maxSearchResults;
      final noResults = items.isEmpty;
      final errorMessage = noResults
          ? offset == 0
                ? '没有找到相关番剧。'
                : '当前页没有匹配结果，请继续翻页。'
          : null;
      _cacheSearchPage(
        cacheKey,
        _CachedSearchPage(
          items: items,
          hasNext: hasNext,
          noResults: noResults,
          error: errorMessage,
          total: page.total,
        ),
      );
      setState(() {
        _searchItems = items;
        _searchLoading = false;
        _searchHasNext = hasNext;
        _searchNoResults = noResults;
        _searchError = errorMessage;
      });
      AppLogger.info(
        'bangumi',
        '搜索完成: "$query"，第 ${offset ~/ _searchPageSize + 1} 页，'
            '${items.length} 部（接口总数 ${page.total}）',
      );
    } catch (error, stackTrace) {
      AppLogger.warning('bangumi', '搜索番剧失败: "$query"', error, stackTrace);
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        _searchItems = const [];
        _searchLoading = false;
        _searchHasNext = false;
        _searchNoResults = false;
        _searchError = '搜索失败，请检查网络连接和设置页日志。';
      });
    }
  }

  String _searchCacheKey(String query, int offset) {
    return '${_normalizeSearchText(query)}\u0000$offset';
  }

  void _cacheSearchPage(String key, _CachedSearchPage page) {
    _searchPageCache.remove(key);
    _searchPageCache[key] = page;
    while (_searchPageCache.length > _maxCachedSearchPages) {
      _searchPageCache.remove(_searchPageCache.keys.first);
    }
  }

  Future<void> _changeSearchPage(int delta) async {
    if (_searchLoading || _searchQuery.isEmpty) return;
    final nextOffset = _searchPageOffset + delta * _searchPageSize;
    if (nextOffset < 0 || nextOffset >= _maxSearchResults) return;
    if (delta > 0 && !_searchHasNext) return;
    await _loadSearchPage(_searchQuery, nextOffset);
  }

  bool _matchesSearchKeyword(BangumiSubject subject, String query) {
    final normalizedQuery = _normalizeSearchText(query);
    if (normalizedQuery.isEmpty) return false;
    final candidates = [subject.name, subject.nameCn, ...subject.aliases];
    return candidates.any(
      (candidate) => _normalizeSearchText(candidate).contains(normalizedQuery),
    );
  }

  String _normalizeSearchText(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  }

  void _selectWeekday(int weekday) {
    if (_selectedWeekday == weekday) return;
    setState(() => _selectedWeekday = weekday);
  }

  Future<void> _toggleFavorite(AnimeItem item) async {
    await AnimeStorageService.toggleFavorite(item);
    await _loadLibrary();
  }

  Future<void> _openItem(AnimeItem item) async {
    await AnimeStorageService.addHistory(item);
    await _loadLibrary();
    if (!mounted) return;
    AppLogger.info('ui', '打开内容详情: ${item.title}');
    showDialog<void>(
      context: context,
      builder: (context) => PreviewDialog(
        item: item,
        isFavorite: _favorites.any((saved) => saved.id == item.id),
        onFavorite: () {
          Navigator.of(context).pop();
          unawaited(_toggleFavorite(item));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _buildRail(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: KeyedSubtree(
                key: ValueKey(_selectedPage),
                child: _buildPage(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRail() {
    return Container(
      width: 88,
      color: const Color(0xFF0B0D11),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 18),
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Text(
                'ZZZ',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(height: 42),
            _buildRailButton(4, Icons.search_rounded, '搜索'),
            _buildRailButton(0, Icons.home_rounded, '首页'),
            _buildRailButton(1, Icons.calendar_month_outlined, '日期表'),
            _buildRailButton(2, Icons.bookmark_border_rounded, '片单'),
            const Spacer(),
            _buildRailButton(3, Icons.tune_rounded, '设置'),
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildRailButton(int index, IconData icon, String label) {
    final selected = _selectedPage == index;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Tooltip(
        message: label,
        child: FocusableWidget(
          autofocus: index == 0,
          onTap: () {
            AppLogger.debug('ui', '切换页面: $label');
            setState(() => _selectedPage = index);
          },
          builder: (context, focused) {
            final active = focused || selected;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 68,
              height: 66,
              decoration: BoxDecoration(
                color: focused
                    ? Theme.of(context).colorScheme.primary
                    : selected
                    ? Theme.of(context).colorScheme.primary.withOpacity(0.16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: selected && !focused
                    ? Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withOpacity(0.5),
                      )
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 24,
                    color: active
                        ? (focused
                              ? Colors.black
                              : Theme.of(context).colorScheme.primary)
                        : Colors.white54,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: focused
                          ? Colors.black
                          : selected
                          ? Colors.white
                          : Colors.white54,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPage() {
    switch (_selectedPage) {
      case 1:
        return SchedulePage(
          key: const ValueKey('schedule'),
          calendarDays: _calendarDays,
          calendarLoading: _calendarLoading,
          calendarError: _calendarError,
          selectedWeekday: _selectedWeekday,
          onWeekdayChanged: _selectWeekday,
          onToggleFavorite: _toggleFavorite,
          onOpen: (item) => unawaited(_openItem(item)),
          isFavorite: (item) => _favorites.any((saved) => saved.id == item.id),
        );
      case 2:
        return CollectionPage(
          key: const ValueKey('collection'),
          favorites: _favorites,
          history: _history,
          onToggleFavorite: _toggleFavorite,
          onOpen: (item) => unawaited(_openItem(item)),
        );
      case 3:
        return const SettingsPage(key: ValueKey('settings'));
      case 4:
        return SearchPage(
          key: const ValueKey('search'),
          items: _searchItems,
          loading: _searchLoading,
          error: _searchError,
          noResults: _searchNoResults,
          initialQuery: _searchQuery,
          pageNumber: _searchPageOffset ~/ _searchPageSize + 1,
          hasPrevious: _searchPageOffset > 0,
          hasNext: _searchHasNext,
          onSearch: _searchAnime,
          onPageChanged: (delta) => unawaited(_changeSearchPage(delta)),
          onOpen: (item) => unawaited(_openItem(item)),
        );
      default:
        return HomeDashboard(
          key: const ValueKey('dashboard'),
          popularItems: _popularItems,
          popularLoading: _popularLoading,
          popularError: _popularError,
          onOpenSchedule: () => setState(() => _selectedPage = 1),
          onOpen: (item) => unawaited(_openItem(item)),
        );
    }
  }
}

class LegacyHomeDashboard extends StatelessWidget {
  final DateTime now;
  final List<AnimeItem> popularItems;
  final bool popularLoading;
  final String? popularError;
  final bool calendarAvailable;
  final String? calendarError;
  final int favoriteCount;
  final int historyCount;
  final bool Function(AnimeItem item) isFavorite;
  final VoidCallback onOpenSchedule;
  final VoidCallback onOpenCollection;
  final ValueChanged<AnimeItem> onOpen;
  final Future<void> Function(AnimeItem item) onToggleFavorite;

  const LegacyHomeDashboard({
    super.key,
    required this.now,
    required this.popularItems,
    required this.popularLoading,
    required this.popularError,
    required this.calendarAvailable,
    required this.calendarError,
    required this.favoriteCount,
    required this.historyCount,
    required this.isFavorite,
    required this.onOpenSchedule,
    required this.onOpenCollection,
    required this.onOpen,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final featured = popularItems.isEmpty ? null : popularItems.first;

    return AppPage(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 24, 38, 42),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              eyebrow: popularItems.isEmpty
                  ? 'ZZZFUN / BANGUMI'
                  : 'ZZZFUN / FOR YOU',
              title: '今天看点什么？',
              subtitle: popularItems.isEmpty
                  ? popularLoading
                        ? '正在同步 Bangumi 热门番剧。'
                        : '热门番剧获取失败，请检查网络或前往设置查看日志。'
                  : '从 Bangumi 热度数据中挑选值得关注的番剧。',
              trailing: Text(
                _formatTime(now),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 22),
            if (featured != null)
              LegacyFeaturedBanner(
                item: featured,
                isFavorite: isFavorite(featured),
                onOpen: () => onOpen(featured),
                onFavorite: () => onToggleFavorite(featured),
              )
            else
              _DataStatePanel(
                loading: popularLoading,
                title: popularLoading ? '正在获取热门番剧' : '热门番剧获取失败',
                message: popularLoading
                    ? '正在连接 Bangumi 元数据接口，请稍候。'
                    : '接口没有返回可展示的内容，请检查当前网络连接和设置页日志。',
                icon: popularLoading
                    ? Icons.sync_rounded
                    : Icons.cloud_off_outlined,
              ),
            const SizedBox(height: 30),
            SectionHeading(
              title: '热门番剧',
              caption: featured == null ? '暂无数据' : '${popularItems.length} 部',
              trailing: TextButton.icon(
                onPressed: onOpenSchedule,
                icon: const Icon(Icons.calendar_month_outlined, size: 17),
                label: const Text('查看日期表'),
              ),
            ),
            const SizedBox(height: 15),
            if (popularItems.isNotEmpty)
              SizedBox(
                height: 304,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: popularItems.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 16),
                  itemBuilder: (context, index) {
                    final item = popularItems[index];
                    return PreviewCard(
                      width: 170,
                      item: item,
                      isFavorite: isFavorite(item),
                      onTap: () => onOpen(item),
                      onFavorite: () => onToggleFavorite(item),
                    );
                  },
                ),
              )
            else
              const SizedBox(
                height: 180,
                child: Center(
                  child: Text(
                    '暂无可展示的热门番剧',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              ),
            const SizedBox(height: 30),
            Row(
              children: [
                Expanded(
                  child: _MetricTile(
                    icon: Icons.bookmark_outline_rounded,
                    label: '我的收藏',
                    value: '$favoriteCount',
                    onTap: onOpenCollection,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _MetricTile(
                    icon: Icons.history_rounded,
                    label: '观看历史',
                    value: '$historyCount',
                    onTap: onOpenCollection,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _MetricTile(
                    icon: calendarAvailable
                        ? Icons.cloud_done_outlined
                        : calendarError != null
                        ? Icons.cloud_off_outlined
                        : Icons.sync_rounded,
                    label: '放送日历',
                    value: calendarAvailable
                        ? '已同步'
                        : calendarError != null
                        ? '失败'
                        : '同步中',
                    onTap: onOpenSchedule,
                  ),
                ),
              ],
            ),
            if (popularError != null) ...[
              const SizedBox(height: 18),
              const _InlineNotice(
                icon: Icons.info_outline_rounded,
                message: '热门番剧接口没有返回数据，未使用本地预览替代。可在设置页查看详细日志。',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class LegacyFeaturedBanner extends StatelessWidget {
  final AnimeItem item;
  final bool isFavorite;
  final VoidCallback onOpen;
  final VoidCallback onFavorite;

  const LegacyFeaturedBanner({
    super.key,
    required this.item,
    required this.isFavorite,
    required this.onOpen,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        final height = compact ? 438.0 : 360.0;
        return SizedBox(
          height: height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              fit: StackFit.expand,
              children: [
                PosterBackdrop(item: item),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        const Color(0xFF08090C).withOpacity(0.98),
                        const Color(0xFF08090C).withOpacity(0.72),
                        const Color(0xFF08090C).withOpacity(0.08),
                      ],
                      stops: compact ? const [0, 0.75, 1] : const [0, 0.48, 1],
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        const Color(0xFF08090C).withOpacity(0.9),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: compact ? 22 : 30,
                  right: compact ? 22 : constraints.maxWidth * 0.42,
                  bottom: compact ? 24 : 30,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '精选推荐',
                        style: TextStyle(
                          color: primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 30 : 36,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _ItemMeta(item: item),
                      const SizedBox(height: 12),
                      Text(
                        item.description,
                        maxLines: compact ? 3 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          height: 1.5,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          FilledButton.icon(
                            onPressed: onOpen,
                            icon: const Icon(
                              Icons.info_outline_rounded,
                              size: 18,
                            ),
                            label: const Text('查看详情'),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            onPressed: onFavorite,
                            tooltip: isFavorite ? '取消收藏' : '加入收藏',
                            icon: Icon(
                              isFavorite
                                  ? Icons.bookmark_rounded
                                  : Icons.bookmark_border_rounded,
                              size: 20,
                            ),
                          ),
                        ],
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

class HomeDashboard extends StatefulWidget {
  final List<AnimeItem> popularItems;
  final bool popularLoading;
  final String? popularError;
  final VoidCallback onOpenSchedule;
  final ValueChanged<AnimeItem> onOpen;

  const HomeDashboard({
    super.key,
    required this.popularItems,
    required this.popularLoading,
    required this.popularError,
    required this.onOpenSchedule,
    required this.onOpen,
  });

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  int _featuredIndex = 0;

  @override
  void didUpdateWidget(covariant HomeDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.popularItems.isEmpty ||
        _featuredIndex >= widget.popularItems.take(8).length) {
      _featuredIndex = 0;
    }
  }

  void _moveFeatured(int delta) {
    final featuredCount = widget.popularItems.take(8).length;
    if (featuredCount < 2) return;
    setState(() {
      _featuredIndex = (_featuredIndex + delta + featuredCount) % featuredCount;
    });
  }

  @override
  Widget build(BuildContext context) {
    final carouselItems = widget.popularItems.take(8).toList(growable: false);
    final carouselIndex = carouselItems.isEmpty
        ? 0
        : _featuredIndex.clamp(0, carouselItems.length - 1).toInt();
    final featured = carouselItems.isEmpty
        ? null
        : carouselItems[carouselIndex];

    return AppPage(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 18, 38, 42),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (featured != null)
              HeroBanner(
                items: carouselItems,
                selectedIndex: carouselIndex,
                onIndexChanged: (index) =>
                    setState(() => _featuredIndex = index),
                onPrevious: () => _moveFeatured(-1),
                onNext: () => _moveFeatured(1),
                onOpen: () => widget.onOpen(featured),
              )
            else
              _DataStatePanel(
                loading: widget.popularLoading,
                title: widget.popularLoading ? '正在获取热门番剧' : '热门番剧获取失败',
                message: widget.popularLoading
                    ? '正在连接 Bangumi 元数据接口，请稍候。'
                    : '接口没有返回可展示的内容，请检查当前网络连接和设置页日志。',
                icon: widget.popularLoading
                    ? Icons.sync_rounded
                    : Icons.cloud_off_outlined,
              ),
            const SizedBox(height: 28),
            SectionHeading(
              title: '热门番剧',
              caption: widget.popularItems.isEmpty
                  ? '暂无数据'
                  : '${widget.popularItems.length} 部',
              trailing: TextButton.icon(
                onPressed: widget.onOpenSchedule,
                icon: const Icon(Icons.calendar_month_outlined, size: 17),
                label: const Text('查看日期表'),
              ),
            ),
            const SizedBox(height: 18),
            if (widget.popularItems.isEmpty)
              const SizedBox(
                height: 180,
                child: Center(
                  child: Text(
                    '热门番剧获取失败',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 760
                      ? 5
                      : constraints.maxWidth >= 600
                      ? 4
                      : constraints.maxWidth >= 560
                      ? 3
                      : 2;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: widget.popularItems.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      childAspectRatio: 0.55,
                      crossAxisSpacing: 22,
                      mainAxisSpacing: 26,
                    ),
                    itemBuilder: (context, index) {
                      final item = widget.popularItems[index];
                      return PreviewCard(
                        item: item,
                        onTap: () => widget.onOpen(item),
                      );
                    },
                  );
                },
              ),
            if (widget.popularError != null) ...[
              const SizedBox(height: 18),
              const _InlineNotice(
                icon: Icons.info_outline_rounded,
                message: '热门番剧接口没有返回数据，未使用本地预览替代。可在设置页查看详细日志。',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class SearchPage extends StatefulWidget {
  final List<AnimeItem> items;
  final bool loading;
  final String? error;
  final bool noResults;
  final String initialQuery;
  final int pageNumber;
  final bool hasPrevious;
  final bool hasNext;
  final Future<void> Function(String query) onSearch;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<AnimeItem> onOpen;

  const SearchPage({
    super.key,
    required this.items,
    required this.loading,
    required this.error,
    required this.noResults,
    required this.initialQuery,
    required this.pageNumber,
    required this.hasPrevious,
    required this.hasNext,
    required this.onSearch,
    required this.onPageChanged,
    required this.onOpen,
  });

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final TextEditingController _queryController;
  late final FocusNode _queryFocusNode;
  late final FocusNode _firstResultFocusNode;
  late final FocusNode _previousPageFocusNode;
  late final FocusNode _nextPageFocusNode;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.initialQuery);
    _queryFocusNode = FocusNode(debugLabel: 'ZZZFunSearchInput');
    _queryFocusNode.onKeyEvent = _handleQueryKeyEvent;
    _firstResultFocusNode = FocusNode(debugLabel: 'ZZZFunSearchFirstResult');
    _previousPageFocusNode = FocusNode(debugLabel: 'ZZZFunSearchPreviousPage');
    _nextPageFocusNode = FocusNode(debugLabel: 'ZZZFunSearchNextPage');
  }

  @override
  void didUpdateWidget(covariant SearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialQuery != widget.initialQuery &&
        _queryController.text != widget.initialQuery) {
      _queryController.value = TextEditingValue(
        text: widget.initialQuery,
        selection: TextSelection.collapsed(offset: widget.initialQuery.length),
      );
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    _queryFocusNode.dispose();
    _firstResultFocusNode.dispose();
    _previousPageFocusNode.dispose();
    _nextPageFocusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleQueryKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (widget.items.isNotEmpty) {
        _firstResultFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (widget.hasNext) {
        _nextPageFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (widget.hasPrevious) {
        _previousPageFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleResultKeyEvent(
    int index,
    int columns,
    FocusNode node,
    KeyEvent event,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp && index < columns) {
      _queryFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
        index >= widget.items.length - columns) {
      final target = widget.hasNext
          ? _nextPageFocusNode
          : widget.hasPrevious
          ? _previousPageFocusNode
          : null;
      if (target != null) {
        target.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  int _gridColumnCount(double width) {
    return ((width + 16) / (190 + 16)).floor().clamp(1, 20).toInt();
  }

  void _submit() {
    unawaited(widget.onSearch(_queryController.text));
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 38, 28),
        child: Column(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: TextField(
                  controller: _queryController,
                  focusNode: _queryFocusNode,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _submit(),
                  style: const TextStyle(fontSize: 17),
                  decoration: InputDecoration(
                    hintText: '搜索动漫',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: widget.loading
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFF28262D),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 18,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.08),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Expanded(child: _buildResults()),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (widget.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.error != null) {
      return Column(
        children: [
          Expanded(
            child: EmptyState(
              icon: widget.noResults
                  ? Icons.search_off_rounded
                  : Icons.cloud_off_outlined,
              title: widget.noResults ? '没有找到相关番剧' : '搜索失败',
              message: widget.error!,
            ),
          ),
          if (widget.noResults && (widget.hasPrevious || widget.hasNext))
            _buildPageControls(),
        ],
      );
    }
    if (widget.items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading(title: '搜索结果'),
        const SizedBox(height: 18),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = _gridColumnCount(constraints.maxWidth);
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(6, 8, 6, 20),
                itemCount: widget.items.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 190,
                  childAspectRatio: 0.55,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 24,
                ),
                itemBuilder: (context, index) {
                  final item = widget.items[index];
                  return PreviewCard(
                    item: item,
                    focusNode: index == 0 ? _firstResultFocusNode : null,
                    onKeyEvent: (node, event) =>
                        _handleResultKeyEvent(index, columns, node, event),
                    onTap: () => widget.onOpen(item),
                  );
                },
              );
            },
          ),
        ),
        _buildPageControls(),
      ],
    );
  }

  Widget _buildPageControls() {
    if (!widget.hasPrevious && !widget.hasNext) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildPageButton(
          tooltip: '上一页',
          icon: Icons.chevron_left_rounded,
          focusNode: _previousPageFocusNode,
          enabled: widget.hasPrevious && !widget.loading,
          onTap: () => widget.onPageChanged(-1),
        ),
        Text(
          '第 ${widget.pageNumber} 页',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        _buildPageButton(
          tooltip: '下一页',
          icon: Icons.chevron_right_rounded,
          focusNode: _nextPageFocusNode,
          enabled: widget.hasNext && !widget.loading,
          onTap: () => widget.onPageChanged(1),
        ),
      ],
    );
  }

  Widget _buildPageButton({
    required String tooltip,
    required IconData icon,
    required FocusNode focusNode,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: FocusableWidget(
        focusNode: focusNode,
        enabled: enabled,
        onTap: onTap,
        builder: (context, focused) {
          final primary = Theme.of(context).colorScheme.primary;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: focused
                  ? primary
                  : Colors.white.withValues(alpha: enabled ? 0.08 : 0.03),
              shape: BoxShape.circle,
              border: focused
                  ? Border.all(color: primary.withValues(alpha: 0.55), width: 2)
                  : null,
            ),
            child: Icon(
              icon,
              size: 20,
              color: focused
                  ? Colors.black
                  : enabled
                  ? Colors.white70
                  : Colors.white24,
            ),
          );
        },
      ),
    );
  }
}

class LegacyCarouselBanner extends StatelessWidget {
  final List<AnimeItem> items;
  final int selectedIndex;
  final bool isFavorite;
  final ValueChanged<int> onIndexChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onOpen;
  final VoidCallback onFavorite;

  const LegacyCarouselBanner({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.isFavorite,
    required this.onIndexChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onOpen,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final item = items[selectedIndex];
    final primary = Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        return FocusableWidget(
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              onPrevious();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              onNext();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          builder: (context, focused) => SizedBox(
            height: compact ? 180 : 170,
            child: ClipRRect(
              borderRadius: BorderRadius.zero,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      child: SizedBox.expand(
                        key: ValueKey(item.id),
                        child: PosterBackdrop(item: item),
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.black.withOpacity(0.24),
                          Colors.transparent,
                          Colors.black.withOpacity(0.16),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: compact ? 16 : 30,
                    top: 12,
                    child: Row(
                      children: [
                        FilledButton.icon(
                          onPressed: onOpen,
                          icon: const Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                          ),
                          label: const Text('查看详情'),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          onPressed: onFavorite,
                          tooltip: isFavorite ? '取消收藏' : '加入收藏',
                          icon: Icon(
                            isFavorite
                                ? Icons.bookmark_rounded
                                : Icons.bookmark_border_rounded,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (items.length > 1)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 12,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var index = 0; index < items.length; index++)
                            GestureDetector(
                              onTap: () => onIndexChanged(index),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
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
          ),
        );
      },
    );
  }
}

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
              onPrevious();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
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
                      _ItemMeta(item: item),
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

class SchedulePage extends StatelessWidget {
  final List<BangumiCalendarDay> calendarDays;
  final bool calendarLoading;
  final String? calendarError;
  final int selectedWeekday;
  final ValueChanged<int> onWeekdayChanged;
  final Future<void> Function(AnimeItem item) onToggleFavorite;
  final ValueChanged<AnimeItem> onOpen;
  final bool Function(AnimeItem item) isFavorite;

  const SchedulePage({
    super.key,
    required this.calendarDays,
    required this.calendarLoading,
    required this.calendarError,
    required this.selectedWeekday,
    required this.onWeekdayChanged,
    required this.onToggleFavorite,
    required this.onOpen,
    required this.isFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final selectedDay = _findDay(selectedWeekday);
    final items =
        selectedDay?.subjects
            .map(AnimeItem.fromBangumi)
            .toList(growable: false) ??
        const <AnimeItem>[];

    return AppPage(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 24, 38, 42),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _WeekdaySelector(
              days: calendarDays,
              selectedWeekday: selectedWeekday,
              onChanged: onWeekdayChanged,
            ),
            if (calendarError != null) ...[
              const SizedBox(height: 16),
              const _InlineNotice(
                icon: Icons.cloud_off_outlined,
                message: '放送日历获取失败，当前没有可展示的更新数据。请检查网络或前往设置查看日志。',
              ),
            ],
            const SizedBox(height: 28),
            SectionHeading(
              title: selectedDay?.weekdayCn ?? _weekdayLabel(selectedWeekday),
              caption: items.isEmpty ? '暂无数据' : '${items.length} 部更新',
            ),
            const SizedBox(height: 18),
            if (calendarLoading && calendarDays.isEmpty)
              const SizedBox(
                height: 260,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (items.isEmpty)
              const SizedBox(
                height: 260,
                child: EmptyState(
                  icon: Icons.event_busy_outlined,
                  title: '当天没有可展示的番剧',
                  message: '接口没有返回该日期的放送内容。',
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 190,
                  childAspectRatio: 0.55,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 24,
                ),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return PreviewCard(
                    item: item,
                    isFavorite: isFavorite(item),
                    onTap: () => onOpen(item),
                    onFavorite: () => onToggleFavorite(item),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  BangumiCalendarDay? _findDay(int weekday) {
    for (final day in calendarDays) {
      if (day.weekdayId == weekday) return day;
    }
    return null;
  }
}

class _WeekdaySelector extends StatelessWidget {
  final List<BangumiCalendarDay> days;
  final int selectedWeekday;
  final ValueChanged<int> onChanged;

  const _WeekdaySelector({
    required this.days,
    required this.selectedWeekday,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 7,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final weekday = index + 1;
          final day = _dayFor(weekday);
          final selected = weekday == selectedWeekday;
          return SizedBox(
            width: 82,
            child: Material(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : const Color(0xFF171A20),
              borderRadius: BorderRadius.circular(9),
              child: InkWell(
                onTap: () => onChanged(weekday),
                borderRadius: BorderRadius.circular(9),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _weekdayLabel(weekday),
                        style: TextStyle(
                          color: selected ? Colors.black : Colors.white70,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        day == null ? '暂无数据' : '${day.subjects.length} 部',
                        style: TextStyle(
                          color: selected ? Colors.black54 : Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  BangumiCalendarDay? _dayFor(int weekday) {
    for (final day in days) {
      if (day.weekdayId == weekday) return day;
    }
    return null;
  }
}

class CollectionPage extends StatelessWidget {
  final List<AnimeItem> favorites;
  final List<AnimeItem> history;
  final Future<void> Function(AnimeItem item) onToggleFavorite;
  final ValueChanged<AnimeItem> onOpen;

  const CollectionPage({
    super.key,
    required this.favorites,
    required this.history,
    required this.onToggleFavorite,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return AppPage(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 38, 24),
        child: DefaultTabController(
          length: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: '我的收藏  ${favorites.length}'),
                  Tab(text: '观看历史  ${history.length}'),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(
                child: TabBarView(
                  children: [
                    _LibraryGrid(
                      items: favorites,
                      emptyIcon: Icons.bookmark_border_rounded,
                      emptyTitle: '还没有收藏',
                      emptyMessage: '在首页或日期表收藏喜欢的番剧，它们会保存在这里。',
                      isFavorite: true,
                      onOpen: onOpen,
                      onFavorite: onToggleFavorite,
                    ),
                    _LibraryGrid(
                      items: history,
                      emptyIcon: Icons.history_rounded,
                      emptyTitle: '还没有观看记录',
                      emptyMessage: '打开番剧详情后，最近浏览的内容会显示在这里。',
                      onOpen: onOpen,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryGrid extends StatelessWidget {
  final List<AnimeItem> items;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;
  final bool isFavorite;
  final ValueChanged<AnimeItem> onOpen;
  final Future<void> Function(AnimeItem item)? onFavorite;

  const _LibraryGrid({
    required this.items,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.onOpen,
    this.isFavorite = false,
    this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return EmptyState(
        icon: emptyIcon,
        title: emptyTitle,
        message: emptyMessage,
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        childAspectRatio: 0.55,
        crossAxisSpacing: 16,
        mainAxisSpacing: 24,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return PreviewCard(
          item: item,
          isFavorite: isFavorite,
          onTap: () => onOpen(item),
          onFavorite: onFavorite == null ? null : () => onFavorite!(item),
        );
      },
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPage(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 38, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PageHeader(
              eyebrow: 'ZZZFUN / SETTINGS',
              title: '设置与日志',
              subtitle: '查看应用状态、内容源状态和最近运行日志。',
            ),
            const SizedBox(height: 22),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 680;
                final tiles = [
                  const _StatusTile(
                    icon: Icons.check_circle_outline,
                    title: '应用状态',
                    value: '运行正常',
                    color: Color(0xFF5ED49A),
                  ),
                  _StatusTile(
                    icon: Icons.storage_outlined,
                    title: '数据模式',
                    value: '仅本地',
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const _StatusTile(
                    icon: Icons.link_off_rounded,
                    title: '播放资源',
                    value: '未配置',
                    color: Colors.white54,
                  ),
                ];
                return compact
                    ? Column(
                        children: [
                          for (
                            var index = 0;
                            index < tiles.length;
                            index++
                          ) ...[
                            tiles[index],
                            if (index != tiles.length - 1)
                              const SizedBox(height: 10),
                          ],
                        ],
                      )
                    : Row(
                        children: [
                          for (
                            var index = 0;
                            index < tiles.length;
                            index++
                          ) ...[
                            Expanded(child: tiles[index]),
                            if (index != tiles.length - 1)
                              const SizedBox(width: 14),
                          ],
                        ],
                      );
              },
            ),
            const SizedBox(height: 24),
            SectionHeading(
              title: '运行日志',
              caption: '最近 300 条',
              trailing: ValueListenableBuilder<List<LogEntry>>(
                valueListenable: AppLogger.entries,
                builder: (context, entries, _) => Row(
                  children: [
                    Text(
                      '${entries.length} 条',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: entries.isEmpty ? null : AppLogger.clear,
                      tooltip: '清空日志',
                      icon: const Icon(Icons.delete_sweep_outlined),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ValueListenableBuilder<List<LogEntry>>(
                valueListenable: AppLogger.entries,
                builder: (context, entries, _) {
                  if (entries.isEmpty) {
                    return const EmptyState(
                      icon: Icons.article_outlined,
                      title: '还没有日志',
                      message: '应用运行事件会显示在这里。',
                    );
                  }
                  return Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF111318),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(14),
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => Divider(
                        color: Colors.white.withOpacity(0.05),
                        height: 14,
                      ),
                      itemBuilder: (context, index) {
                        final entry = entries[entries.length - index - 1];
                        return Text(
                          entry.line,
                          style: TextStyle(
                            color: _logColor(entry.level),
                            fontFamily: 'Consolas',
                            fontSize: 12,
                            height: 1.35,
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PreviewCard extends StatelessWidget {
  final AnimeItem item;
  final bool isFavorite;
  final double? width;
  final FocusNode? focusNode;
  final KeyEventResult Function(FocusNode node, KeyEvent event)? onKeyEvent;
  final VoidCallback onTap;
  final VoidCallback? onFavorite;

  const PreviewCard({
    super.key,
    required this.item,
    this.isFavorite = false,
    this.width,
    this.focusNode,
    this.onKeyEvent,
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
              _ItemMeta(item: item, compact: true),
            ],
          ),
        );
      },
    );
    return SizedBox(width: width, child: card);
  }
}

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

class PreviewDialog extends StatelessWidget {
  final AnimeItem item;
  final bool isFavorite;
  final VoidCallback? onFavorite;

  const PreviewDialog({
    super.key,
    required this.item,
    required this.isFavorite,
    this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF191C22),
      insetPadding: const EdgeInsets.all(18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 570;
          final details = _details(context);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 230,
                        width: 164,
                        child: PosterArt(item: item),
                      ),
                      const SizedBox(height: 20),
                      details,
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 246,
                        width: 174,
                        child: PosterArt(item: item),
                      ),
                      const SizedBox(width: 24),
                      Expanded(child: details),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _details(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.title,
          style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        _ItemMeta(item: item),
        const SizedBox(height: 18),
        Text(
          item.description,
          style: const TextStyle(color: Colors.white70, height: 1.55),
        ),
        const SizedBox(height: 18),
        if (item.tags.isNotEmpty)
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: item.tags
                .take(6)
                .map(
                  (tag) => Chip(
                    label: Text(tag),
                    labelStyle: const TextStyle(fontSize: 11),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide.none,
                  ),
                )
                .toList(),
          ),
        const SizedBox(height: 20),
        const _InlineNotice(
          icon: Icons.info_outline_rounded,
          message: '当前已接入番剧元数据，播放资源和视频链接将在后续内容源确定后接入。',
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
            if (onFavorite != null) ...[
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: onFavorite,
                icon: Icon(
                  isFavorite
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  size: 18,
                ),
                label: Text(isFavorite ? '取消收藏' : '加入收藏'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class AppPage extends StatelessWidget {
  final Widget child;

  const AppPage({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: const Color(0xFF0E1014), child: child);
  }
}

class PageHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget? trailing;

  const PageHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 29,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 14), trailing!],
      ],
    );
  }
}

class _ItemMeta extends StatelessWidget {
  final AnimeItem item;
  final bool compact;

  const _ItemMeta({required this.item, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (item.score != null && item.score! > 0)
        '★ ${item.score!.toStringAsFixed(1)}',
      if (item.airDate != null && item.airDate!.isNotEmpty)
        item.airDate!.split('-').first,
      if (item.episodeCount != null && item.episodeCount! > 0)
        '${item.episodeCount} 集',
    ];
    if (parts.isEmpty) parts.add(item.category);
    return Text(
      parts.join('  ·  '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: item.score != null && item.score! > 0
            ? Theme.of(context).colorScheme.primary
            : Colors.white54,
        fontSize: compact ? 11 : 13,
        fontWeight: compact ? FontWeight.w400 : FontWeight.w600,
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF15181E),
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: Theme.of(context).colorScheme.primary,
                size: 21,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;

  const _StatusTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF15181E),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _DataStatePanel extends StatelessWidget {
  final bool loading;
  final String title;
  final String message;
  final IconData icon;

  const _DataStatePanel({
    required this.loading,
    required this.title,
    required this.message,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      height: 300,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF15181E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: loading ? primary : Colors.white38),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 7),
            Text(
              message,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  final IconData icon;
  final String message;

  const _InlineNotice({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF15181E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white54),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color _logColor(LogLevel level) {
  switch (level) {
    case LogLevel.debug:
      return Colors.white54;
    case LogLevel.info:
      return const Color(0xFFB9C7D8);
    case LogLevel.warning:
      return const Color(0xFFFFC267);
    case LogLevel.error:
      return const Color(0xFFFF8787);
  }
}

String _weekdayLabel(int weekday) {
  const names = ['一', '二', '三', '四', '五', '六', '日'];
  if (weekday < 1 || weekday > 7) return '日期';
  return '周${names[weekday - 1]}';
}

String _formatTime(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
