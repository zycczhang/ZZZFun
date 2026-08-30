import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zzzfun/models/anime_models.dart';
import 'package:zzzfun/pages/anime_detail_page.dart';
import 'package:zzzfun/services/video_resource_service.dart';

void main() {
  testWidgets('TV Back closes detail without popping its host route', (
    tester,
  ) async {
    await tester.pumpWidget(const _TestApp());
    await tester.pump();

    expect(find.byKey(const ValueKey('detail')), findsOneWidget);

    // A TV remote can deliver a key event before Android dispatches system
    // back. The detail page must leave goBack for PopScope in that case.
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.goBack,
      physicalKey: PhysicalKeyboardKey.keyA,
    );
    await tester.sendKeyUpEvent(
      LogicalKeyboardKey.goBack,
      physicalKey: PhysicalKeyboardKey.keyA,
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('detail')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.byKey(const ValueKey('detail')), findsNothing);
    expect(find.byKey(const ValueKey('detail-closed')), findsOneWidget);
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      initialRoute: '/detail',
      onGenerateRoute: (settings) {
        if (settings.name == '/') {
          return MaterialPageRoute<void>(
            builder: (_) => const ColoredBox(color: Colors.black),
          );
        }
        return MaterialPageRoute<void>(builder: (_) => const _DetailHost());
      },
    );
  }
}

class _DetailHost extends StatefulWidget {
  const _DetailHost();

  @override
  State<_DetailHost> createState() => _DetailHostState();
}

class _DetailHostState extends State<_DetailHost> {
  final VideoResourceService _resourceService = VideoResourceService();
  bool _showDetail = true;

  @override
  void dispose() {
    unawaited(_resourceService.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_showDetail) {
      return const ColoredBox(
        key: ValueKey('detail-closed'),
        color: Colors.black,
      );
    }
    return AnimeDetailPage(
      key: const ValueKey('detail'),
      item: const AnimeItem(
        id: 'test-anime',
        title: '测试番剧',
        subtitle: '',
        category: '测试',
        tag: '测试',
        description: '详情页返回测试',
        colorSeed: 0,
      ),
      isFavorite: false,
      onBack: () => setState(() => _showDetail = false),
      onToggleFavorite: () {},
      resourceService: _resourceService,
    );
  }
}
