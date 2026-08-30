import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zzzfun/models/anime_models.dart';
import 'package:zzzfun/models/kazumi_rule_models.dart';
import 'package:zzzfun/models/video_source_models.dart';
import 'package:zzzfun/models/watch_history_models.dart';
import 'package:zzzfun/pages/anime_detail_page.dart';
import 'package:zzzfun/services/anime_storage_service.dart';
import 'package:zzzfun/services/video_resource_service.dart';

void main() {
  test(
    'stores playback details and evicts the oldest entry after 100',
    () async {
      SharedPreferences.setMockInitialValues({});

      for (var index = 0; index <= 100; index++) {
        await AnimeStorageService.saveHistory(
          WatchHistoryEntry(
            item: _item('anime-$index'),
            sourceSite: 'site-$index',
            sourceLine: 'line-$index',
            searchItemName: 'search-$index',
            searchItemSource: 'https://example.com/search/$index',
            episodeName: '第${index + 1}集',
            episodeIndex: index,
            episodeUrl: 'https://example.com/episode/$index',
            positionMs: index * 60 * 1000,
            durationMs: 30 * 60 * 1000,
          ),
        );
      }

      final history = await AnimeStorageService.getHistory();

      expect(history, hasLength(AnimeStorageService.maxHistoryCount));
      expect(history.first.item.id, 'anime-100');
      expect(history.last.item.id, 'anime-1');
      expect(
        history.first.displaySummary,
        'site-100 · line-100\n第101集 · 1:40:00',
      );
    },
  );

  test(
    'updates an existing anime history entry instead of duplicating it',
    () async {
      SharedPreferences.setMockInitialValues({});

      await AnimeStorageService.saveHistory(
        WatchHistoryEntry(
          item: _item('anime-1'),
          sourceSite: 'site-a',
          sourceLine: 'line-a',
          positionMs: 60 * 1000,
        ),
      );
      await AnimeStorageService.saveHistory(
        WatchHistoryEntry(item: _item('anime-2'), sourceSite: 'site-b'),
      );
      await AnimeStorageService.saveHistory(
        WatchHistoryEntry(
          item: _item('anime-1'),
          sourceSite: 'site-c',
          sourceLine: 'line-c',
          positionMs: 5 * 60 * 1000,
        ),
      );

      final history = await AnimeStorageService.getHistory();

      expect(history, hasLength(2));
      expect(history.first.item.id, 'anime-1');
      expect(history.first.sourceSite, 'site-c');
      expect(history.first.position, const Duration(minutes: 5));
    },
  );

  test('reads legacy anime-only history entries', () async {
    final item = _item('legacy-anime');
    SharedPreferences.setMockInitialValues({
      'zzzfun_history': jsonEncode([item.toJson()]),
    });

    final history = await AnimeStorageService.getHistory();

    expect(history.single.item.id, item.id);
    expect(history.single.hasPlaybackSelection, isFalse);
  });

  test(
    'extracts source, line, episode and position from a playback selection',
    () {
      const episode = VideoEpisode(
        name: '第3集',
        pageUrl: 'https://example.com/episode/3',
        roadIndex: 1,
        episodeIndex: 2,
      );
      final selection = VideoPlaybackSelection(
        rule: KazumiRule.fromJson({'name': 'source-site'}),
        searchItem: const VideoSearchItem(
          name: '测试番剧',
          source: 'https://example.com/search/test',
          ruleName: 'source-site',
        ),
        chapters: VideoChapterResult(
          ruleName: 'source-site',
          source: 'https://example.com/search/test',
          sources: const [
            VideoSource(name: '线路 A', episodes: [episode]),
            VideoSource(name: '线路 B', episodes: [episode]),
          ],
        ),
        episode: episode,
      );

      final history = WatchHistoryEntry.fromSelection(
        item: _item('anime-selection'),
        selection: selection,
        position: const Duration(minutes: 7, seconds: 12),
      );

      expect(history.sourceSite, 'source-site');
      expect(history.sourceLine, '线路 B');
      expect(history.episodeLabel, '第3集');
      expect(history.positionLabel, '07:12');
    },
  );

  testWidgets('uses continue playback text for playable history', (
    tester,
  ) async {
    final service = VideoResourceService();
    final item = _item('anime-continue');
    await tester.pumpWidget(
      MaterialApp(
        home: AnimeDetailPage(
          item: item,
          isFavorite: false,
          historyEntry: WatchHistoryEntry(
            item: item,
            sourceSite: 'site-a',
            sourceLine: 'line-a',
            searchItemSource: 'https://example.com/search/anime-continue',
            episodeName: '第2集',
            episodeIndex: 1,
            episodeUrl: 'https://example.com/episode/2',
            positionMs: 90 * 1000,
          ),
          onBack: () {},
          onToggleFavorite: () {},
          resourceService: service,
        ),
      ),
    );

    expect(find.text('继续播放'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await service.close();
  });
}

AnimeItem _item(String id) => AnimeItem(
  id: id,
  title: id,
  subtitle: '',
  category: '测试',
  tag: '测试',
  description: '测试番剧',
  colorSeed: 0,
);
