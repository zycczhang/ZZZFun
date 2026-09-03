import 'dart:async';

import 'package:flutter/foundation.dart';

class ServerEventBus {
  static final StreamController<String> _controller =
      StreamController<String>.broadcast();

  static Stream<String> get stream => _controller.stream;

  static const eventRefreshData = 'refresh_data';

  static void emit(String event) => _controller.add(event);
}

class WebServerService {
  static const int port = 8080;
  static final ValueNotifier<String> serverUrlNotifier = ValueNotifier<String>(
    '当前平台不支持',
  );

  static String get serverUrl => serverUrlNotifier.value;

  static Future<void> startServer() async {}

  static Future<void> stopServer() async {}
}
