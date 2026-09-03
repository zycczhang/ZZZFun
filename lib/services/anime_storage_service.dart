import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/anime_models.dart';
import '../models/watch_history_models.dart';
import 'app_logger.dart';

class AnimeStorageService {
  static const _favoritesKey = 'zzzfun_favorites';
  static const _historyKey = 'zzzfun_history';
  static const maxHistoryCount = 100;
  static Future<void> _historyWriteQueue = Future<void>.value();

  static Future<List<AnimeItem>> getFavorites() async =>
      _readList(_favoritesKey);

  static Future<List<WatchHistoryEntry>> getHistory() async {
    await _historyWriteQueue;
    return _readHistory();
  }

  static Future<WatchHistoryEntry?> getHistoryEntry(String itemId) async {
    final history = await getHistory();
    for (final entry in history) {
      if (entry.item.id == itemId) return entry;
    }
    return null;
  }

  static Future<bool> toggleFavorite(AnimeItem item) async {
    final favorites = await getFavorites();
    final index = favorites.indexWhere((saved) => saved.id == item.id);
    if (index >= 0) {
      favorites.removeAt(index);
      await _writeList(_favoritesKey, favorites);
      AppLogger.info('library', '已移出收藏: ${item.title}');
      return false;
    }

    favorites.insert(0, item);
    await _writeList(_favoritesKey, favorites);
    AppLogger.info('library', '已加入收藏: ${item.title}');
    return true;
  }

  static Future<int> replaceFavorites(List<AnimeItem> items) async {
    final uniqueItems = <String, AnimeItem>{};
    for (final item in items) {
      if (item.id.isNotEmpty) uniqueItems[item.id] = item;
    }
    final storedItems = uniqueItems.values.toList(growable: false);
    await _writeList(_favoritesKey, storedItems);
    AppLogger.info('library', '已从网页端同步收藏: ${storedItems.length} 条');
    return storedItems.length;
  }

  static Future<void> saveHistory(WatchHistoryEntry entry) {
    final operation = _historyWriteQueue.then((_) async {
      final history = await _readHistory();
      history.removeWhere((saved) => saved.item.id == entry.item.id);
      history.insert(0, entry);
      await _writeHistory(history.take(maxHistoryCount).toList());
    });
    _historyWriteQueue = operation.catchError((_) {});
    return operation;
  }

  static Future<void> clearHistory() async {
    final operation = _historyWriteQueue.then((_) async {
      await _writeHistory([]);
      AppLogger.info('library', '已清空本地历史');
    });
    _historyWriteQueue = operation.catchError((_) {});
    await operation;
  }

  static Future<List<WatchHistoryEntry>> _readHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_historyKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map(
            (item) =>
                WatchHistoryEntry.fromJson(Map<String, dynamic>.from(item)),
          )
          .take(maxHistoryCount)
          .toList();
    } catch (error, stackTrace) {
      AppLogger.error('library', '读取本地历史失败', error, stackTrace);
      return [];
    }
  }

  static Future<List<AnimeItem>> _readList(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => AnimeItem.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (error, stackTrace) {
      AppLogger.error('library', '读取本地片单失败', error, stackTrace);
      return [];
    }
  }

  static Future<void> _writeList(String key, List<AnimeItem> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        key,
        jsonEncode(items.map((item) => item.toJson()).toList()),
      );
    } catch (error, stackTrace) {
      AppLogger.error('library', '保存本地片单失败', error, stackTrace);
    }
  }

  static Future<void> _writeHistory(List<WatchHistoryEntry> entries) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _historyKey,
        jsonEncode(entries.map((entry) => entry.toJson()).toList()),
      );
    } catch (error, stackTrace) {
      AppLogger.error('library', '保存本地历史失败', error, stackTrace);
    }
  }
}
