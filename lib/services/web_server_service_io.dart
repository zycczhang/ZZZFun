import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:shelf_router/shelf_router.dart';

import '../models/anime_models.dart';
import 'anime_storage_service.dart';
import 'app_logger.dart';
import 'bangumi_api_service.dart';

class ServerEventBus {
  static final StreamController<String> _controller =
      StreamController<String>.broadcast();

  static Stream<String> get stream => _controller.stream;

  static const eventRefreshData = 'refresh_data';

  static void emit(String event) => _controller.add(event);
}

class WebServerService {
  static const int port = 8080;
  static HttpServer? _server;
  static BangumiApiService? _bangumiApi;
  static Future<void>? _startOperation;
  static final ValueNotifier<String> serverUrlNotifier = ValueNotifier<String>(
    '未启动',
  );

  static String get serverUrl => serverUrlNotifier.value;

  static Future<void> startServer() {
    if (_server != null) return Future<void>.value();
    return _startOperation ??= _start().whenComplete(() {
      _startOperation = null;
    });
  }

  static Future<void> _start() async {
    final api = BangumiApiService();
    final router = Router();

    router.get('/', _handleIndex);
    router.get('/api/favorites', (Request request) async {
      final favorites = await AnimeStorageService.getFavorites();
      return _jsonResponse({
        'items': favorites.map(_withFavoriteFlag).toList(growable: false),
        'total': favorites.length,
      });
    });

    router.get('/api/search', (Request request) async {
      final keyword = request.url.queryParameters['keyword']?.trim() ?? '';
      if (keyword.isEmpty) {
        return _jsonResponse({'items': const [], 'total': 0, 'hasNext': false});
      }

      final limit = _parseLimit(request.url.queryParameters['limit']);
      final offset = _parseOffset(request.url.queryParameters['offset']);
      try {
        final page = await api.searchSubjects(
          keyword,
          limit: limit,
          offset: offset,
          sort: 'heat',
        );
        final favoriteIds = (await AnimeStorageService.getFavorites())
            .map((item) => item.id)
            .toSet();
        final items = page.subjects
            .where(
              (subject) => [
                subject.name,
                subject.nameCn,
                ...subject.aliases,
              ].any((name) => _matchesKeyword(name, keyword)),
            )
            .map(AnimeItem.fromBangumi)
            .map(
              (item) =>
                  _itemJson(item, isFavorite: favoriteIds.contains(item.id)),
            )
            .toList(growable: false);
        return _jsonResponse({
          'items': items,
          'total': page.total,
          'hasNext':
              page.subjects.length >= limit && offset + limit < page.total,
        });
      } catch (error, stackTrace) {
        AppLogger.warning('web', '网页搜索失败: "$keyword"', error, stackTrace);
        return _jsonResponse({'message': '搜索失败，请检查电视端网络连接。'}, statusCode: 502);
      }
    });

    router.post('/api/favorites/toggle', (Request request) async {
      try {
        final item = _decodeAnimeItem(await request.readAsString());
        await AnimeStorageService.toggleFavorite(item);
        ServerEventBus.emit(ServerEventBus.eventRefreshData);
        return _jsonResponse({'ok': true});
      } catch (error, stackTrace) {
        AppLogger.warning('web', '网页收藏操作失败', error, stackTrace);
        return _jsonResponse({'message': '收藏操作失败。'}, statusCode: 400);
      }
    });

    router.post('/api/favorites/import', (Request request) async {
      try {
        final decoded = jsonDecode(await request.readAsString());
        if (decoded is! List) {
          throw const FormatException('收藏数据必须是数组');
        }
        final items = decoded
            .whereType<Map>()
            .map((item) => AnimeItem.fromJson(Map<String, dynamic>.from(item)))
            .where((item) => item.id.isNotEmpty)
            .toList(growable: false);
        final total = await AnimeStorageService.replaceFavorites(items);
        ServerEventBus.emit(ServerEventBus.eventRefreshData);
        return _jsonResponse({'ok': true, 'total': total});
      } catch (error, stackTrace) {
        AppLogger.warning('web', '网页收藏导入失败', error, stackTrace);
        return _jsonResponse({'message': '导入失败，文件格式不正确。'}, statusCode: 400);
      }
    });

    final handler = const Pipeline()
        .addMiddleware(corsHeaders())
        .addHandler(router.call);

    try {
      final server = await shelf_io.serve(
        handler,
        InternetAddress.anyIPv4,
        port,
      );
      _server = server;
      _bangumiApi = api;
      final ip = await _findLanAddress();
      serverUrlNotifier.value = 'http://$ip:${server.port}';
      AppLogger.info('web', '网页服务已启动: $serverUrl');
    } catch (error, stackTrace) {
      await api.close();
      serverUrlNotifier.value = '启动失败';
      AppLogger.warning('web', '网页服务启动失败', error, stackTrace);
    }
  }

  static Future<void> stopServer() async {
    final server = _server;
    _server = null;
    serverUrlNotifier.value = '已停止';
    await server?.close(force: true);
    final api = _bangumiApi;
    _bangumiApi = null;
    await api?.close();
  }

  static Future<Response> _handleIndex(Request request) async {
    try {
      final html = await rootBundle.loadString('assets/index.html');
      return Response.ok(
        html,
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    } catch (error, stackTrace) {
      AppLogger.warning('web', '加载网页资源失败', error, stackTrace);
      return Response.internalServerError(body: '网页资源加载失败');
    }
  }

  static Map<String, dynamic> _withFavoriteFlag(AnimeItem item) {
    return _itemJson(item, isFavorite: true);
  }

  static Map<String, dynamic> _itemJson(
    AnimeItem item, {
    required bool isFavorite,
  }) {
    return {...item.toJson(), 'isFavorite': isFavorite};
  }

  static AnimeItem _decodeAnimeItem(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) throw const FormatException('收藏数据格式无效');
    return AnimeItem.fromJson(Map<String, dynamic>.from(decoded));
  }

  static int _parseLimit(String? value) {
    return (int.tryParse(value ?? '') ?? 20).clamp(1, 50).toInt();
  }

  static int _parseOffset(String? value) {
    return (int.tryParse(value ?? '') ?? 0).clamp(0, 100).toInt();
  }

  static bool _matchesKeyword(String value, String keyword) {
    final normalizedValue = _normalize(value);
    final normalizedKeyword = _normalize(keyword);
    return normalizedKeyword.isNotEmpty &&
        normalizedValue.contains(normalizedKeyword);
  }

  static String _normalize(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  }

  static Response _jsonResponse(Object body, {int statusCode = 200}) {
    return Response(
      statusCode,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  static Future<String> _findLanAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback) return address.address;
        }
      }
    } catch (error, stackTrace) {
      AppLogger.warning('web', '获取局域网地址失败', error, stackTrace);
    }
    return '127.0.0.1';
  }
}
