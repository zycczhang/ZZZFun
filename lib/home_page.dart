import 'dart:async';

import 'package:flutter/material.dart';

import 'anime_nav_widgets.dart';
import 'models/anime_models.dart';
import 'models/bangumi_models.dart';
import 'pages/collection_page.dart';
import 'pages/home_dashboard_page.dart';
import 'pages/schedule_page.dart';
import 'pages/search_page.dart';
import 'pages/settings_page.dart';
import 'services/anime_storage_service.dart';
import 'services/app_logger.dart';
import 'services/bangumi_api_service.dart';
import 'services/video_resource_service.dart';
import 'pages/anime_detail_page.dart';

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
  final VideoResourceService _videoResources = VideoResourceService();

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
  AnimeItem? _detailItem;
  bool _detailLoading = false;
  final Map<int, AnimeItem> _subjectDetailCache = <int, AnimeItem>{};
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
    _videoResources.close();
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
    if (!mounted) return;
    final cachedItem = item.bangumiId == null
        ? null
        : _subjectDetailCache[item.bangumiId!];
    setState(() {
      _detailItem = cachedItem ?? item;
      _detailLoading = item.bangumiId != null && cachedItem == null;
    });
    await AnimeStorageService.addHistory(item);
    await _loadLibrary();
    AppLogger.info('ui', '打开内容详情: ${item.title}');
    final subjectId = item.bangumiId;
    if (subjectId == null || _subjectDetailCache.containsKey(subjectId)) {
      if (mounted && _detailItem?.id == item.id) {
        setState(() => _detailLoading = false);
      }
      return;
    }
    try {
      final subject = await _bangumiApi.getSubject(subjectId);
      final detailedItem = AnimeItem.fromBangumi(subject);
      _subjectDetailCache[subjectId] = detailedItem;
      if (!mounted || _detailItem?.id != item.id) return;
      setState(() {
        _detailItem = detailedItem;
        _detailLoading = false;
      });
      AppLogger.info('bangumi', '番剧详情已加载: ${detailedItem.title}');
    } catch (error, stackTrace) {
      AppLogger.warning(
        'bangumi',
        '番剧详情补全失败: ${item.title}',
        error,
        stackTrace,
      );
      if (mounted && _detailItem?.id == item.id) {
        setState(() => _detailLoading = false);
      }
    }
  }

  void _closeDetail() {
    if (_detailItem == null) return;
    setState(() {
      _detailItem = null;
      _detailLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final detailItem = _detailItem;
    if (detailItem != null) {
      return AnimeDetailPage(
        item: detailItem,
        isFavorite: _favorites.any((saved) => saved.id == detailItem.id),
        loadingDetails: _detailLoading,
        onBack: _closeDetail,
        onToggleFavorite: () => unawaited(_toggleFavorite(detailItem)),
        resourceService: _videoResources,
      );
    }
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
            if (index == 3) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) =>
                      SettingsPage(resourceService: _videoResources),
                ),
              );
              return;
            }
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
