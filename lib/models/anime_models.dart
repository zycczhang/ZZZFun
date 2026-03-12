import '../services/anime_api_service.dart';
//线路模型
//name: omofun动漫（线路x）
//url:  https://omofun99.top
class RouteItem {
  final String name;
  final String url;
  RouteItem({required this.name, required this.url});
}

class HomeData {
  final List<AnimeItem> banners;
  final List<WeeklyData> weeklyAnime;
  HomeData({required this.banners, required this.weeklyAnime});
}

//搜索结果模型
class SearchResult {
  final List<AnimeItem> items;
  final bool hasNextPage;
  SearchResult({required this.items, required this.hasNextPage});
}

// --- 数据模型 ---
class AnimeItem {
  final String title;
  final String imageUrl;
  final String note;
  final String url;
  // 新增：用于存储历史记录的详细进度信息 {sourceIndex, episodeName, positionSeconds}
  final Map<String, dynamic>? playbackInfo;

  AnimeItem({
    required this.title,
    required this.imageUrl,
    required this.note,
    required this.url,
    this.playbackInfo,
  });

  // 修改：保存时去除域名，只存相对路径
  Map<String, dynamic> toJson() {
    String saveUrl = url;
    // 获取当前配置的 BaseUrl
    String currentBaseUrl = AnimeApiService.baseUrl;

    // 如果 URL 包含当前的域名，则截取掉，只保留后面的路径 (如 /vod/detail/id/123.html)
    if (url.startsWith(currentBaseUrl)) {
      saveUrl = url.substring(currentBaseUrl.length);
    }

    return {
      'title': title,
      'imageUrl': imageUrl,
      'note': note,
      'url': saveUrl,
      // 保存进度信息
      if (playbackInfo != null) 'playbackInfo': playbackInfo,
    };
  }

  // 修改：读取时如果发现是相对路径，自动拼接当前最新的 BaseUrl
  factory AnimeItem.fromJson(Map<String, dynamic> json) {
    String loadUrl = json['url'] ?? "";

    // 如果是相对路径 (以 / 开头)，拼上最新的 baseUrl
    if (loadUrl.startsWith('/')) {
      loadUrl = "${AnimeApiService.baseUrl}$loadUrl";
    }

    return AnimeItem(
      title: json['title'] ?? "",
      imageUrl: json['imageUrl'] ?? "",
      note: json['note'] ?? "",
      url: loadUrl, // 内存中恢复为完整链接，供播放器使用
      playbackInfo: json['playbackInfo'],
    );
  }
}


class WeeklyData {
  final String day;
  final List<AnimeItem> items;
  WeeklyData({required this.day, required this.items});
}

class Episode {
  final String name;
  final String url;
  Episode({required this.name, required this.url});
}

class PlaySource {
  final String sourceName;
  final List<Episode> episodes;
  PlaySource({required this.sourceName, required this.episodes});
}

class AnimeDetail {
  final String title;
  final String imageUrl;
  final String introduction;
  final String updateTime;
  final List<PlaySource> playSources;
  AnimeDetail({required this.title, required this.imageUrl, required this.introduction, required this.updateTime, required this.playSources});
}

