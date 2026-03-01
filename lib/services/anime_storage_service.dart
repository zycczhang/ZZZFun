import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/anime_models.dart';
import 'anime_api_service.dart'; // 需要用到 baseUrl

// --- 本地存储服务 ---
class AnimeStorageService {
  static const String _keyFavorites = 'anime_favorites';
  static const String _keyHistory = 'anime_history'; // 新增key
  static const String _keyBaseUrl = 'anime_base_url'; // 新增：保存BaseUrl的key

  // 保存选中的 BaseUrl
  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBaseUrl, url);
  }
  // 获取保存的 BaseUrl (如果为空则返回默认)
  static Future<String?> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyBaseUrl);
  }

  // 获取所有收藏
  static Future<List<AnimeItem>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonString = prefs.getString(_keyFavorites);
    if (jsonString == null) return [];

    List<dynamic> jsonList = jsonDecode(jsonString);
    // 这里调用 fromJson，会自动将相对路径转为当前域名的完整路径
    //print('🔍 获取到的原始收藏JSON数据: $jsonList');
    return jsonList.map((e) => AnimeItem.fromJson(e)).toList();
  }

  // [新增] 根据 URL 获取单条历史记录
  static Future<AnimeItem?> getHistoryItem(String url) async {
    final list = await getHistory();
    String targetPath = _getPath(url);
    try {
      // 查找路径匹配的第一条记录
      return list.firstWhere((e) => _getPath(e.url) == targetPath);
    } catch (e) {
      // 没找到
      return null;
    }
  }

  // 辅助方法：提取 URL 的路径部分 (忽略域名)
  // 比如 https://omofun03.top/vod/detail/123.html -> /vod/detail/123.html
  static String _getPath(String fullUrl) {
    try {
      if (fullUrl.startsWith('/')) return fullUrl; // 已经是相对路径
      Uri uri = Uri.parse(fullUrl);
      return uri.path;
    } catch (e) {
      return fullUrl;
    }
  }

  // 检查是否已收藏 (修改为比较路径)
  static Future<bool> isFavorite(String url) async {
    final list = await getFavorites();
    String targetPath = _getPath(url);
    // 只要路径相同就视为已收藏
    return list.any((item) => _getPath(item.url) == targetPath);
  }

  // 添加收藏
  static Future<void> addFavorite(AnimeItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getFavorites();

    String targetPath = _getPath(item.url);

    // 避免重复添加 (比较路径)
    if (!list.any((e) => _getPath(e.url) == targetPath)) {
      list.add(item);
      // 保存时会自动调用 toJson 去除域名
      await prefs.setString(_keyFavorites, jsonEncode(list.map((e) => e.toJson()).toList()));
    }
  }

  // 取消收藏 (修改为比较路径)
  static Future<void> removeFavorite(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getFavorites();

    String targetPath = _getPath(url);
    list.removeWhere((item) => _getPath(item.url) == targetPath);

    await prefs.setString(_keyFavorites, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  // --- 新增：历史记录功能 ---

  // 获取历史记录
  static Future<List<AnimeItem>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonString = prefs.getString(_keyHistory);
    if (jsonString == null) return [];
    List<dynamic> jsonList = jsonDecode(jsonString);
    return jsonList.map((e) => AnimeItem.fromJson(e)).toList();
  }

  // 添加/更新历史记录
  static Future<void> addHistory(AnimeItem item) async {
    final prefs = await SharedPreferences.getInstance();
    List<AnimeItem> list = await getHistory();

    String targetPath = _getPath(item.url);

    // 1. 如果已存在，先删除（为了把它移动到最上面）
    list.removeWhere((e) => _getPath(e.url) == targetPath);

    // 2. 插入到头部（最新的在最上面）
    list.insert(0, item);

    // 3. 限制数量为100
    if (list.length > 100) {
      list = list.sublist(0, 100);
    }

    // 4. 保存
    await prefs.setString(_keyHistory, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  // 可选：清空历史记录
  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyHistory);
  }

  // 可选：删除单条历史记录
  static Future<void> removeHistory(String url) async {
    final prefs = await SharedPreferences.getInstance();
    List<AnimeItem> list = await getHistory();
    String targetPath = _getPath(url);
    list.removeWhere((item) => _getPath(item.url) == targetPath);
    await prefs.setString(_keyHistory, jsonEncode(list.map((e) => e.toJson()).toList()));
  }
}