import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../anime_nav_widgets.dart';
import '../models/anime_models.dart';
import '../widgets/anime_preview_card.dart';
import '../widgets/app_ui.dart';

class SearchPage extends StatefulWidget {
  final List<AnimeItem> items;
  final bool loading;
  final String? error;
  final bool noResults;
  final String initialQuery;
  final int pageNumber;
  final bool hasPrevious;
  final bool hasNext;
  final FocusNode queryFocusNode;
  final FocusNode navigationFocusNode;
  final ValueListenable<String> webServerUrl;
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
    required this.queryFocusNode,
    required this.navigationFocusNode,
    required this.webServerUrl,
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
  late final FocusNode _searchActionFocusNode;
  bool _isEditingQuery = false;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.initialQuery);
    _queryFocusNode = widget.queryFocusNode;
    _queryFocusNode.onKeyEvent = _handleQueryKeyEvent;
    _queryFocusNode.addListener(_handleQueryFocusChange);
    _firstResultFocusNode = FocusNode(debugLabel: 'ZZZFunSearchFirstResult');
    _previousPageFocusNode = FocusNode(debugLabel: 'ZZZFunSearchPreviousPage');
    _nextPageFocusNode = FocusNode(debugLabel: 'ZZZFunSearchNextPage');
    _searchActionFocusNode = FocusNode(debugLabel: 'ZZZFunSearchAction');
    _searchActionFocusNode.onKeyEvent = _handleSearchActionKeyEvent;
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
    unawaited(_hideSystemKeyboard());
    _queryController.dispose();
    _queryFocusNode.onKeyEvent = null;
    _queryFocusNode.removeListener(_handleQueryFocusChange);
    _firstResultFocusNode.dispose();
    _previousPageFocusNode.dispose();
    _nextPageFocusNode.dispose();
    _searchActionFocusNode.dispose();
    super.dispose();
  }

  void _handleQueryFocusChange() {
    if (!_queryFocusNode.hasFocus && _isEditingQuery && mounted) {
      setState(() => _isEditingQuery = false);
    }
  }

  bool _isActivateKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space;
  }

  void _beginQueryEditing() {
    if (_isEditingQuery) return;
    _queryFocusNode.requestFocus();
    setState(() => _isEditingQuery = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isEditingQuery || !_queryFocusNode.hasFocus) return;
      unawaited(_showSystemKeyboard());
    });
  }

  void _stopQueryEditing() {
    if (!_isEditingQuery) return;
    setState(() => _isEditingQuery = false);
    unawaited(_hideSystemKeyboard());
  }

  KeyEventResult _handleQueryKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (!_isEditingQuery && _isActivateKey(event.logicalKey)) {
      _beginQueryEditing();
      return KeyEventResult.handled;
    }

    if (_isEditingQuery && event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _stopQueryEditing();
      _searchActionFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    if (!_isEditingQuery && event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _searchActionFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    if (_isEditingQuery && event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _stopQueryEditing();
      widget.navigationFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    if (!_isEditingQuery && event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      widget.navigationFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_isEditingQuery) _stopQueryEditing();
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

  KeyEventResult _handleSearchActionKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      widget.navigationFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
        widget.items.isNotEmpty) {
      _firstResultFocusNode.requestFocus();
      return KeyEventResult.handled;
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
    _stopQueryEditing();
    FocusManager.instance.primaryFocus?.unfocus();
    _searchActionFocusNode.requestFocus();
    unawaited(widget.onSearch(_queryController.text));
  }

  Future<void> _showSystemKeyboard() async {
    try {
      await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    } catch (_) {
      // Desktop and widget-test text input channels may not be available.
    }
  }

  Future<void> _hideSystemKeyboard() async {
    try {
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    } catch (_) {
      // Desktop and widget-test text input channels may not be available.
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 38, 28),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildSearchHeader()),
            ..._buildResultSlivers(),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchHeader() {
    return Column(
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queryController,
                    focusNode: _queryFocusNode,
                    autofocus: false,
                    readOnly: !_isEditingQuery,
                    showCursor: _isEditingQuery,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.search,
                    onTap: _beginQueryEditing,
                    onSubmitted: (_) {
                      if (_isEditingQuery) {
                        _submit();
                      } else {
                        _beginQueryEditing();
                      }
                    },
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
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
                          color: Colors.white.withValues(alpha: 0.08),
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
                const SizedBox(width: 12),
                _buildSearchAction(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _buildWebServerAddress(),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _buildSearchAction() {
    return Tooltip(
      message: '搜索',
      child: FocusableWidget(
        focusNode: _searchActionFocusNode,
        enabled: !widget.loading,
        onTap: _submit,
        builder: (context, focused) {
          final primary = Theme.of(context).colorScheme.primary;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 112,
            height: 58,
            decoration: BoxDecoration(
              color: focused ? primary : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: focused
                  ? Border.all(color: primary.withValues(alpha: 0.7), width: 2)
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: focused ? Colors.black : Colors.white70,
                ),
                const SizedBox(width: 7),
                Text(
                  '搜索',
                  style: TextStyle(
                    color: focused ? Colors.black : Colors.white70,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildWebServerAddress() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ValueListenableBuilder<String>(
          valueListenable: widget.webServerUrl,
          builder: (context, url, child) {
            final running = url.startsWith('http');
            final address = running
                ? url
                : url == '未启动'
                ? '网页地址获取中...'
                : url;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Text(
                    '网页端操作：',
                    style: TextStyle(
                      color: running ? Colors.white70 : Colors.white38,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    Icons.language_rounded,
                    size: 22,
                    color: running
                        ? Theme.of(context).colorScheme.primary
                        : Colors.white38,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: running ? Colors.white60 : Colors.white38,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
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

  List<Widget> _buildResultSlivers() {
    if (widget.loading) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (widget.error != null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: widget.noResults
                ? Icons.search_off_rounded
                : Icons.cloud_off_outlined,
            title: widget.noResults ? '没有找到相关番剧' : '搜索失败',
            message: widget.error!,
          ),
        ),
        if (widget.noResults && (widget.hasPrevious || widget.hasNext))
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: _buildPageControls(),
            ),
          ),
      ];
    }
    if (widget.items.isEmpty) return const [];

    return [
      const SliverToBoxAdapter(child: SectionHeading(title: '搜索结果')),
      const SliverToBoxAdapter(child: SizedBox(height: 18)),
      SliverLayoutBuilder(
        builder: (context, constraints) {
          final columns = _gridColumnCount(constraints.crossAxisExtent);
          return SliverPadding(
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 20),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate((context, index) {
                final item = widget.items[index];
                return PreviewCard(
                  item: item,
                  focusNode: index == 0 ? _firstResultFocusNode : null,
                  onKeyEvent: (node, event) =>
                      _handleResultKeyEvent(index, columns, node, event),
                  onTap: () => widget.onOpen(item),
                );
              }, childCount: widget.items.length),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 190,
                childAspectRatio: 0.55,
                crossAxisSpacing: 16,
                mainAxisSpacing: 24,
              ),
            ),
          );
        },
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: _buildPageControls(),
        ),
      ),
    ];
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
