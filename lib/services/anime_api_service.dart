import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;
import '../models/anime_models.dart';
import '../HeadlessWeb.dart';
import 'anime_storage_service.dart';
// --- 网络请求/数据抓取 ---
class AnimeApiService {
  // 修改：去掉 const，改为静态变量，默认值保留一个可用的
  static String baseUrl = 'https://omofun03.top';
  // 发布页地址
  static const String publishPageUrl = 'https://omofun111.top/';
  // 统一的请求头管理
  static Map<String, String> _getHeaders({String? referer}) {
    return {
      'User-Agent': 'Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 CrKey/1.54.248666 Edg/143.0.0.0',
      'Referer': referer ?? baseUrl,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6',
    };
  }
  // 1. 获取周更表
  static Future<List<WeeklyData>> fetchAnimeData() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        var document = parse(response.body);
        var modules = document.querySelectorAll('.module');
        var targetModule = modules.firstWhere(
              (m) => m.querySelector('.module-title')?.text.contains("一月新番") ?? false,
          orElse: () => modules.first,
        );

        var tabs = targetModule.querySelectorAll('.module-tab-item');
        var lists = targetModule.querySelectorAll('.module-main.tab-list');

        List<WeeklyData> tempList = [];
        for (int i = 0; i < tabs.length; i++) {
          String day = tabs[i].attributes['data-dropdown-value'] ?? "";
          List<AnimeItem> items = [];
          var animeNodes = lists[i].querySelectorAll('.module-item');

          for (var node in animeNodes) {
            var img = node.querySelector('img');
            String relativeUrl = node.attributes['href'] ?? "";
            String fullUrl = relativeUrl.startsWith('http') ? relativeUrl : "$baseUrl$relativeUrl";

            items.add(AnimeItem(
              title: node.attributes['title'] ?? "",
              imageUrl: img?.attributes['data-original'] ?? img?.attributes['src'] ?? "",
              note: node.querySelector('.module-item-note')?.text ?? "",
              url: fullUrl,
            ));
          }
          tempList.add(WeeklyData(day: day, items: items));
        }
        return tempList;
      } else {
        throw Exception("请求失败：状态码 ${response.statusCode}");
      }
    } catch (e) {
      print("数据抓取失败: $e");
      rethrow;
    }
  }
  // 2. 获取动画详情
  static Future<AnimeDetail> fetchAnimeDetail(String url) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: _getHeaders(referer: baseUrl),
      );
      if (response.statusCode == 200) {
        var document = parse(response.body);
        String title = document.querySelector('.module-info-heading h1')?.text ?? "未知";

        String imageUrl = "";
        var picElement = document.querySelector('.module-item-pic img');
        if (picElement != null) {
          imageUrl = picElement.attributes['data-original'] ?? picElement.attributes['src'] ?? "";
        } else {
          imageUrl = document.querySelector('.module-info-poster img')?.attributes['data-original'] ?? "";
        }

        String intro = document.querySelector('.module-info-introduction-content')?.text.trim() ?? "";
        String updateTime = "";
        var items = document.querySelectorAll('.module-info-item');
        for (var item in items) {
          if (item.text.contains("更新：")) {
            updateTime = item.querySelector('.module-info-item-content')?.text ?? "";
          }
        }
        var sourceNodes = document.querySelectorAll('.module-tab-item.tab-item');
        List<String> sourceNames = sourceNodes.map((e) => e.querySelector('span')?.text ?? "").toList();
        var listContainers = document.querySelectorAll('.module-list.tab-list');
        List<PlaySource> playSources = [];
        for (int i = 0; i < sourceNames.length; i++) {
          List<Episode> episodes = [];
          if (i < listContainers.length) {
            var links = listContainers[i].querySelectorAll('.module-play-list-link');
            for (var link in links) {
              String relativeEpisodeUrl = link.attributes['href'] ?? "";
              String fullEpisodeUrl = relativeEpisodeUrl.startsWith('http') ? relativeEpisodeUrl : "$baseUrl$relativeEpisodeUrl";
              episodes.add(Episode(
                name: link.querySelector('span')?.text ?? "",
                url: fullEpisodeUrl,
              ));
            }
          }

          //播放线路过滤
          if(sourceNames[i] =="动漫专线"){
            sourceNames[i]="这个很卡";
          }

          playSources.add(PlaySource(sourceName: sourceNames[i], episodes: episodes));

        }
        return AnimeDetail(
          title: title,
          imageUrl: imageUrl,
          introduction: intro,
          updateTime: updateTime,
          playSources: playSources,
        );
      } else {
        throw Exception("详情页请求失败");
      }
    } catch (e) {
      print("抓取详情异常: $e");
      rethrow;
    }
  }
  // 3. 获取视频真实播放地址
  static Future<String> getRealVideoUrl(String playPageUrl) async {
    try {
      // 步骤 1: 尝试使用轻量级的 http 请求 (速度快)
      print("正在请求视频页面(HTTP模式): $playPageUrl");
      final response = await http.get(
        Uri.parse(playPageUrl),
        headers: _getHeaders(referer: playPageUrl),
      );
      if (response.statusCode == 200) {
        String html = response.body;
        // 1.1 尝试从静态 HTML 中直接提取 player_aaaa JS 对象
        RegExp regExp = RegExp(r'var\s+player_aaaa\s*=\s*(\{.*?\});', dotAll: true);
        Match? match = regExp.firstMatch(html);
        if (match != null) {
          String jsonStr = match.group(1)!;
          try {
            Map<String, dynamic> data = jsonDecode(jsonStr);
            String url = data['url'] ?? "";
            if (url.startsWith('http')) {
              print("HTTP模式提取成功 (JSON): $url");
              return url.replaceAll(r'\/', '/');
            }
          } catch (e) {
            // JSON解析失败，尝试正则提取
            RegExp urlReg = RegExp(r'url"\s*:\s*"([^"]+)"');
            Match? urlMatch = urlReg.firstMatch(jsonStr);
            if (urlMatch != null && urlMatch.group(1)!.startsWith('http')) {
              print("HTTP模式提取成功 (正则): ${urlMatch.group(1)}");
              return urlMatch.group(1)!.replaceAll(r'\/', '/');
            }
          }
        }

        // 1.2 尝试从静态 HTML 中直接匹配 <video> 标签 (针对服务端已渲染的情况)
        // 修正后的正则：使用双引号包裹，内部匹配单引号或双引号
        RegExp videoTagReg = RegExp(r"<video[^>]+src\s*=\s*['\x22]([^'\x22]+)['\x22]", caseSensitive: false);
        Match? videoMatch = videoTagReg.firstMatch(html);
        if (videoMatch != null) {
          String tempUrl = videoMatch.group(1)!;
          if (tempUrl.startsWith('http')) {
            print("HTTP模式提取成功 (Video标签): $tempUrl");
            return tempUrl;
          }
        }
      }

      // 方案 2: 如果 HTTP 请求中无法提取到url，启动无头浏览器方案 (模拟浏览器渲染)

      //动漫专线这个线路，http的响应中没有视频的url地址，只能用无头浏览器把网页跑着再提取视频地址
      //这个方法有点慢，但好像本来他的接口就慢，用浏览器播放这个线路的视频，也要等好一会才出来

      print("HTTP模式未找到链接，启动 WebView 渲染模式 (较慢，请稍候)...");
      return await HeadlessWeb.fetchVideoUrl(playPageUrl);

    } catch (e) {
      print("提取过程发生异常: $e");
    }
    return "";
  }
  // 4. 搜索功能
  static Future<SearchResult> searchAnime(String keyword, {int page = 1}) async {
    try {
      // 构造URL
      // 第一页通常使用查询参数: /vod/search.html?wd=xxx
      // 后续分页通常使用路径参数: /vod/search/page/2/wd/xxx.html
      // 为了统一和简单，我们尽量适配服务端的分页逻辑

      String requestUrl;
      if (page == 1) {
        requestUrl = '$baseUrl/vod/search.html?wd=$keyword';
      } else {
        // 注意：URL中的中文需要编码，但通常服务端路径中的编码可能各有不同
        // 这里使用Uri.encodeComponent进行编码
        requestUrl = '$baseUrl/vod/search/page/$page/wd/$keyword.html';
      }
      print("正在搜索: $requestUrl");
      final response = await http.get(
        Uri.parse(requestUrl),
        headers: _getHeaders(),
      );
      if (response.statusCode == 200) {
        var document = parse(response.body);

        // 解析列表
        var items = <AnimeItem>[];
        var moduleItems = document.querySelectorAll('.module-card-item'); // 根据提供的HTML，搜索结果使用这个类名
        for (var node in moduleItems) {
          // 获取图片
          var imgTag = node.querySelector('.module-item-pic img');
          String imageUrl = imgTag?.attributes['data-original'] ?? imgTag?.attributes['src'] ?? "";

          // 获取链接
          var linkTag = node.querySelector('.module-card-item-poster'); // 或者是 .module-card-item-title > a
          String href = linkTag?.attributes['href'] ?? "";
          String fullUrl = href.startsWith('http') ? href : "$baseUrl$href";

          // 获取标题
          var titleTag = node.querySelector('.module-card-item-title a strong') ?? node.querySelector('.module-card-item-title a');
          String title = titleTag?.text.trim() ?? "";

          // 获取状态/备注
          String note = node.querySelector('.module-item-note')?.text ?? "";
          items.add(AnimeItem(
              title: title,
              imageUrl: imageUrl,
              note: note,
              url: fullUrl
          ));
        }
        // 判断是否有下一页
        // 逻辑：检查分页栏中是否有 text 为 "下一页" 的链接，且 href 不为 javascript:;
        bool hasNext = false;
        var pageLinks = document.querySelectorAll('.page-link');
        for (var link in pageLinks) {
          if (link.text.contains("下一页") || link.attributes['title'] == '下一页') {
            String nextHref = link.attributes['href'] ?? "";
            // 简单的判断，如果下一页的链接包含具体路径，则认为有下一页
            if (nextHref.contains("/page/")) {
              hasNext = true;
            }
            break;
          }
        }
        return SearchResult(items: items, hasNextPage: hasNext);
      } else {
        throw Exception("搜索请求失败: ${response.statusCode}");
      }
    } catch (e) {
      print("搜索异常: $e");
      // 发生错误返回空列表
      return SearchResult(items: [], hasNextPage: false);
    }
  }
  // [新增] 5. 通过ID获取视频信息 (用于ID搜索)
  static Future<AnimeItem?> getAnimeById(String id) async {
    // 构造完整的详情页 URL
    String url = '$baseUrl/vod/detail/id/$id.html';
    try {
      // 复用已有的 fetchAnimeDetail 方法来获取标题、图片等信息
      AnimeDetail detail = await fetchAnimeDetail(url);

      // 将详情转换为列表项对象，以便在视频卡片中显示
      return AnimeItem(
        title: detail.title,
        imageUrl: detail.imageUrl,
        note: "ID直达", // 给个特殊备注
        url: url,
      );
    } catch (e) {
      print("ID搜索失败: $e");
      return null;
    }
  }
  // [新增] 6. 获取分类库数据 (动画库/电影库等)
  static Future<SearchResult> fetchCategoryData(int typeId, {int page = 1}) async {
    try {
      // 构造URL
      // 第1页: https://omofun03.top/vod/show/id/3.html
      // 第2页: https://omofun03.top/vod/show/id/3/page/2.html
      String requestUrl;
      if (page == 1) {
        requestUrl = '$baseUrl/vod/show/id/$typeId.html';
      } else {
        requestUrl = '$baseUrl/vod/show/id/$typeId/page/$page.html';
      }
      print("正在请求分类库: $requestUrl");
      final response = await http.get(
        Uri.parse(requestUrl),
        headers: _getHeaders(),
      );
      if (response.statusCode == 200) {
        var document = parse(response.body);
        var items = <AnimeItem>[];
        // 解析列表项
        // 根据你提供的HTML，类名是 module-poster-item module-item
        var itemNodes = document.querySelectorAll('.module-item');
        for (var node in itemNodes) {
          // 跳过没有图片的节点（防止选中tab标题等无关元素）
          var imgTag = node.querySelector('.module-item-pic img');
          if (imgTag == null) continue;
          String imageUrl = imgTag.attributes['data-original'] ?? imgTag.attributes['src'] ?? "";
          String title = node.attributes['title'] ?? node.querySelector('.module-poster-item-title')?.text ?? "";
          String note = node.querySelector('.module-item-note')?.text ?? "";
          String href = node.attributes['href'] ?? "";
          String fullUrl = href.startsWith('http') ? href : "$baseUrl$href";
          items.add(AnimeItem(
            title: title,
            imageUrl: imageUrl,
            note: note,
            url: fullUrl,
          ));
        }
        // 解析分页
        bool hasNext = false;
        var pageContainer = document.querySelector('#page');
        if (pageContainer != null) {
          var nextLink = pageContainer.querySelector('.page-next');
          // 如果存在下一页的链接，并且href不为空且不是javascript:;
          if (nextLink != null && (nextLink.attributes['href']?.contains('/page/') ?? false)) {
            hasNext = true;
          }
        }
        return SearchResult(items: items, hasNextPage: hasNext);
      } else {
        throw Exception("分类库请求失败: ${response.statusCode}");
      }
    } catch (e) {
      print("分类库获取异常: $e");
      return SearchResult(items: [], hasNextPage: false);
    }
  }
  // 新增：初始化 BaseUrl (在 main.dart 中调用)
  static Future<void> init() async {
    String? savedUrl = await AnimeStorageService.getBaseUrl();
    if (savedUrl != null && savedUrl.isNotEmpty) {
      // 简单的格式校验，确保没有结尾的 /
      if (savedUrl.endsWith('/')) {
        savedUrl = savedUrl.substring(0, savedUrl.length - 1);
      }
      baseUrl = savedUrl;
      print("已加载本地配置 BaseUrl: $baseUrl");
    }
  }
  // 新增：获取最新可用线路列表
  static Future<List<RouteItem>> fetchAvailableRoutes() async {
    try {
      print("正在获取线路列表: $publishPageUrl");
      final response = await http.get(Uri.parse(publishPageUrl));

      if (response.statusCode == 200) {
        // ========== 关键修复：手动用UTF-8解码响应内容 ==========
        // 避免默认解码方式导致的中文乱码
        String htmlContent = utf8.decode(response.bodyBytes);
        var document = parse(htmlContent);
        // ======================================================

        var urlList = document.querySelector('#url-list');
        if (urlList == null) return [];
        List<RouteItem> routes = [];
        var listItems = urlList.querySelectorAll('li');
        for (var li in listItems) {
          // 解析结构: <div class="url-content"> -> <span>名字</span> -> <a href="url">
          var contentDiv = li.querySelector('.url-content');
          if (contentDiv != null) {
            String name = contentDiv.querySelector('span')?.text.trim() ?? "未知线路";
            String url = contentDiv.querySelector('a')?.attributes['href']?.trim() ?? "";

            // 简单的过滤，必须是http开头
            if (url.startsWith('http')) {
              // 去除末尾斜杠，统一格式
              if (url.endsWith('/')) {
                url = url.substring(0, url.length - 1);
              }
              routes.add(RouteItem(name: name, url: url));
            }
          }
        }

        // ========== 新增的打印逻辑 ==========
        // 1. 打印获取到的线路总数
        print("成功获取线路列表，共 ${routes.length} 条数据");
        // 2. 遍历打印每条线路的详细信息
        // if (routes.isNotEmpty) {
        //   print("线路详情：");
        //   for (int i = 0; i < routes.length; i++) {
        //     print("${i+1}. ${routes[i].name}:${routes[i].url}");
        //   }
        // }
        // ====================================

        return routes;
      }
    } catch (e) {
      print("获取线路失败: $e");
    }
    return [];
  }
// 新增：获取主页所有数据
  static Future<HomeData> fetchHomeData() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/'),
        headers: _getHeaders(),
      );
      if (response.statusCode == 200) {
        var document = parse(response.body);

        // --- 1. 解析轮播图 ---
        List<AnimeItem> banners = [];
        // 这里的选择器根据你提供的HTML：.swiper-big 中的 .swiper-slide
        var bannerNodes = document.querySelectorAll('.swiper-big .swiper-slide:not(.swiper-slide-duplicate)');
        for (var node in bannerNodes) {
          var aTag = node.querySelector('a.banner');
          String title = node.querySelector('.v-title span')?.text ?? "";
          String style = aTag?.attributes['style'] ?? "";

          // 正则提取 background: url(...) 里的链接
          RegExp regExp = RegExp(r'url\((.*?)\)');
          var match = regExp.firstMatch(style);
          String imageUrl = match?.group(1) ?? "";
          String relativeUrl = aTag?.attributes['href'] ?? "";
          String fullUrl = relativeUrl.startsWith('http') ? relativeUrl : "$baseUrl$relativeUrl";
          if (fullUrl.isNotEmpty && title.isNotEmpty) {
            banners.add(AnimeItem(
              title: title,
              imageUrl: imageUrl,
              note: node.querySelector('.v-ins p')?.text ?? "",
              url: fullUrl,
            ));
          }
        }
        // --- 2. 解析新番板块 (周更表) ---
        var modules = document.querySelectorAll('.module');
        var targetModule = modules.firstWhere(
              (m) => m.querySelector('.module-title')?.text.contains("一月新番") ?? false,
          orElse: () => modules.first,
        );
        var tabs = targetModule.querySelectorAll('.module-tab-item');
        var lists = targetModule.querySelectorAll('.module-main.tab-list');
        List<WeeklyData> weeklyList = [];
        for (int i = 0; i < tabs.length; i++) {
          String day = tabs[i].attributes['data-dropdown-value'] ?? "";
          List<AnimeItem> items = [];
          var animeNodes = lists[i].querySelectorAll('.module-item');
          for (var node in animeNodes) {
            var img = node.querySelector('img');
            String relativeUrl = node.attributes['href'] ?? "";
            String fullUrl = relativeUrl.startsWith('http') ? relativeUrl : "$baseUrl$relativeUrl";
            items.add(AnimeItem(
              title: node.attributes['title'] ?? "",
              imageUrl: img?.attributes['data-original'] ?? img?.attributes['src'] ?? "",
              note: node.querySelector('.module-item-note')?.text ?? "",
              url: fullUrl,
            ));
          }
          weeklyList.add(WeeklyData(day: day, items: items));
        }
        return HomeData(banners: banners, weeklyAnime: weeklyList);
      } else {
        throw Exception("加载首页失败");
      }
    } catch (e) {
      print("首页抓取异常: $e");
      rethrow;
    }
  }
}