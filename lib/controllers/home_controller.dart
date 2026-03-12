import 'package:flutter/material.dart';
import '../models/anime_models.dart';
import '../services/anime_api_service.dart';
import 'package:flutter/material.dart'; // 需要引入以使用 precacheImage
class HomeController extends ChangeNotifier {
  bool isLoading = true;
  List<AnimeItem> banners = [];
  List<WeeklyData> weeklyAnime = [];
  int selectedWeekIndex = 0; // 默认选中当天

  Future<void> init() async {
    await refresh();
  }

  Future<void> refresh() async {
    isLoading = true;
    notifyListeners();
    try {
      HomeData data = await AnimeApiService.fetchHomeData();
      banners = data.banners;
      weeklyAnime = data.weeklyAnime;

      // 简单的逻辑：根据当前周几设置默认 Index
      int weekday = DateTime.now().weekday; // 1-7
      // 假设数据里 0是周一，则 weekday-1。具体看解析出来的顺序
      selectedWeekIndex = (weeklyAnime.length >= weekday) ? weekday - 1 : 0;

    } catch (e) {
      print("Home Error: $e");
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void changeWeek(int index) {
    selectedWeekIndex = index;
    notifyListeners();
  }
}