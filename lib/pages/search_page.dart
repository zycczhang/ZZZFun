import 'dart:async';

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
