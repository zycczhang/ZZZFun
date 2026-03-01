import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle; // 必须引入这个用于读取 Assets
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'models/anime_models.dart';
import 'services/anime_api_service.dart';
import 'services/anime_storage_service.dart';
// ServerEventBus 保持不变
class ServerEventBus {
  static final StreamController<String> _controller = StreamController.broadcast();
  static Stream<String> get stream => _controller.stream;
  static void emit(String event) => _controller.sink.add(event);
  static const String eventRefreshData = 'refresh_data';
  static const String eventPlayUrl = 'play_url::';
}

class WebServerService {
  static HttpServer? _server;
  static String serverUrl = "未启动";

  // --- 新增：日志缓冲区 ---
  static final List<String> _logBuffer = [];
  static const int _maxLogLines = 500; // 限制最大行数，防止内存溢出

  // --- 新增：添加日志的方法 ---
  static void addLog(String message) {
    // 添加时间戳
    String time = DateTime.now().toString().split('.')[0];
    String logLine = "[$time] $message";

    _logBuffer.add(logLine);
    if (_logBuffer.length > _maxLogLines) {
      _logBuffer.removeAt(0); // 移除最早的日志
    }
  }

  static Future<void> startServer() async {
    if (_server != null) return;

    final router = Router();

    // 1. 静态网页首页
    router.get('/', _handleIndex);

    // 2. API: 获取收藏 (完整保留原有逻辑)
    router.get('/api/favorites', (Request request) async {
      var data = await AnimeStorageService.getFavorites();
      // 转换为 Map 并添加 isFavorite: true
      List<Map<String, dynamic>> resultList = data.map((e) {
        var json = e.toJson();
        json['isFavorite'] = true; // 收藏夹里的当然是已收藏
        return json;
      }).toList();

      return Response.ok(jsonEncode(resultList),
          headers: {'content-type': 'application/json'});
    });

    // 3. API: 获取历史 (完整保留原有逻辑)
    router.get('/api/history', (Request request) async {
      var data = await AnimeStorageService.getHistory();
      return Response.ok(jsonEncode(data.map((e) => e.toJson()).toList()),
          headers: {'content-type': 'application/json'});
    });

    // 4. API: 搜索 (完整保留原有逻辑，包含收藏状态检查)
    router.get('/api/search/<keyword>', (Request request, String keyword) async {
      try {
        var result = await AnimeApiService.searchAnime(Uri.decodeComponent(keyword));

        // 遍历检查是否已收藏
        List<Map<String, dynamic>> responseList = [];
        for (var item in result.items) {
          var json = item.toJson();
          // 去数据库查一下收藏状态
          bool isFav = await AnimeStorageService.isFavorite(item.url);
          json['isFavorite'] = isFav;
          responseList.add(json);
        }

        return Response.ok(jsonEncode(responseList),
            headers: {'content-type': 'application/json'});
      } catch (e) {
        // 记录错误日志
        addLog("搜索接口错误: $e");
        return Response.internalServerError(body: e.toString());
      }
    });

    // 5. API: 切换收藏状态 (完整保留原有逻辑)
    router.post('/api/favorite/toggle', (Request request) async {
      try {
        String content = await request.readAsString();
        Map<String, dynamic> data = jsonDecode(content);
        AnimeItem item = AnimeItem.fromJson(data);

        bool isFav = await AnimeStorageService.isFavorite(item.url);
        if (isFav) {
          await AnimeStorageService.removeFavorite(item.url);
          addLog("移除收藏: ${item.title}");
        } else {
          await AnimeStorageService.addFavorite(item);
          addLog("添加收藏: ${item.title}");
        }
        ServerEventBus.emit(ServerEventBus.eventRefreshData);
        return Response.ok("success");
      } catch (e) {
        addLog("切换收藏状态错误: $e");
        return Response.internalServerError(body: e.toString());
      }
    });

    // 6. API: 获取baseurl (完整保留)
    router.get('/api/baseurl', (Request request) async {
      return Response.ok(jsonEncode({'url': AnimeApiService.baseUrl}),
          headers: {'content-type': 'application/json'});
    });

    // 7. API: 修改baseurl (完整保留)
    router.post('/api/baseurl', (Request request) async {
      try {
        String content = await request.readAsString();
        Map<String, dynamic> data = jsonDecode(content);
        String newUrl = data['url'];
        AnimeApiService.baseUrl = newUrl;
        await AnimeStorageService.setBaseUrl(newUrl);
        addLog("修改BaseUrl为: $newUrl");
        return Response.ok("success");
      } catch (e) {
        addLog("修改BaseUrl错误: $e");
        return Response.internalServerError(body: e.toString());
      }
    });

    // 8. API: 播放 (完整保留)
    router.post('/api/play', (Request request) async {
      try {
        String content = await request.readAsString();
        Map<String, dynamic> data = jsonDecode(content);
        String url = data['url'];
        String baseUrl = AnimeApiService.baseUrl;
        addLog("播放请求: $baseUrl$url");
        ServerEventBus.emit("${ServerEventBus.eventPlayUrl}$baseUrl$url");
        return Response.ok("playing");
      } catch (e) {
        addLog("播放接口错误: $e");
        return Response.internalServerError(body: e.toString());
      }
    });

    // --- 新增：获取日志的 API ---
    router.get('/api/logs', (Request request) {
      // 返回所有日志列表
      return Response.ok(jsonEncode(_logBuffer),
          headers: {'content-type': 'application/json'});
    });

    // --- 新增：清空日志 API ---
    router.post('/api/logs/clear', (Request request) {
      _logBuffer.clear();
      addLog("日志已清空");
      return Response.ok("cleared");
    });

    final handler = const Pipeline()
        .addMiddleware(corsHeaders())
        .addHandler(router.call);

    try {
      _server = await io.serve(handler, InternetAddress.anyIPv4, 8080);
      List<NetworkInterface> interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
          includeLinkLocal: false
      );
      String ip = "localhost";
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.address.startsWith("127.")) {
            ip = addr.address;
            break;
          }
        }
      }
      serverUrl = "http://$ip:8080";
      addLog('Web Server 启动成功: $serverUrl');
      print('Web Server running at $serverUrl');
    } catch (e) {
      addLog("Server 启动失败: $e");
      print("Server start error: $e");
      serverUrl = "启动失败: $e";
    }
  }

  static void stopServer() {
    addLog("Web Server 已停止");
    _server?.close(force: true);
    _server = null;
  }

  // 读取 Assets 中的首页文件
  static Future<Response> _handleIndex(Request request) async {
    try {
      // 从 assets 读取 HTML 字符串
      String htmlContent = await rootBundle.loadString('assets/index.html');
      return Response.ok(htmlContent, headers: {'content-type': 'text/html; charset=utf-8'});
    } catch (e) {
      addLog("加载首页HTML失败: $e");
      return Response.internalServerError(body: 'Failed to load HTML file: $e');
    }
  }
}