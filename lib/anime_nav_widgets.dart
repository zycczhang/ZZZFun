import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FocusableWidget extends StatefulWidget {
  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback? onTap;
  final KeyEventResult Function(FocusNode node, KeyEvent event)? onKeyEvent;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool enabled;

  const FocusableWidget({
    super.key,
    required this.builder,
    this.onTap,
    this.onKeyEvent,
    this.focusNode,
    this.autofocus = false,
    this.enabled = true,
  });

  @override
  State<FocusableWidget> createState() => _FocusableWidgetState();
}

class _FocusableWidgetState extends State<FocusableWidget> {
  late final FocusNode _internalNode;
  FocusNode get _node => widget.focusNode ?? _internalNode;

  @override
  void initState() {
    super.initState();
    _internalNode = FocusNode(debugLabel: 'ZZZFunFocusable');
    _node.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant FocusableWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_onFocusChanged);
      _node.addListener(_onFocusChanged);
    }
  }

  @override
  void dispose() {
    _node.removeListener(_onFocusChanged);
    _internalNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.enabled) {
      return KeyEventResult.ignored;
    }
    final customResult = widget.onKeyEvent?.call(node, event);
    if (customResult != null && customResult != KeyEventResult.ignored) {
      return customResult;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.gameButtonA) {
      widget.onTap?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      canRequestFocus: widget.enabled,
      onKeyEvent: _onKeyEvent,
      child: GestureDetector(
        onTap: widget.enabled
            ? () {
                _node.requestFocus();
                widget.onTap?.call();
              }
            : null,
        child: widget.builder(context, _node.hasFocus),
      ),
    );
  }
}

class SectionHeading extends StatelessWidget {
  final String title;
  final String? caption;
  final Widget? trailing;

  const SectionHeading({
    super.key,
    required this.title,
    this.caption,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 22,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
        ),
        if (caption != null) ...[
          const SizedBox(width: 12),
          Text(
            caption!,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 13,
            ),
          ),
        ],
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: Colors.white.withValues(alpha: 0.25)),
          const SizedBox(height: 18),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.48)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
