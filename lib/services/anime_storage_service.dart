import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/anime_models.dart';
import 'app_logger.dart';

class AnimeStorageService {
  static const _favoritesKey = 'zzzfun_favorites';
  static const _historyKey = 'zzzfun_history';

  static Future<List<AnimeItem>> getFavorites() async =>
      _readList(_favoritesKey);

  static Future<List<AnimeItem>> getHistory() async => _readList(_historyKey);

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

  static Future<void> addHistory(AnimeItem item) async {
    final history = await getHistory();
    history.removeWhere((saved) => saved.id == item.id);
    history.insert(0, item);
    await _writeList(_historyKey, history.take(50).toList());
  }

  static Future<void> clearHistory() async {
    await _writeList(_historyKey, []);
    AppLogger.info('library', '已清空本地历史');
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
}
