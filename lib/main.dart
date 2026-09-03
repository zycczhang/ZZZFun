import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'home_page.dart';
import 'services/app_logger.dart';
import 'services/web_server_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLogger.initialize();

  FlutterError.onError = (details) {
    AppLogger.error(
      'flutter',
      details.exceptionAsString(),
      details.exception,
      details.stack,
    );
  };

  try {
    await WakelockPlus.enable();
    AppLogger.info('app', 'ZZZFun 已启动');
  } catch (error, stackTrace) {
    AppLogger.warning('app', '无法启用屏幕常亮', error, stackTrace);
  }

  runZonedGuarded(
    () {
      runApp(const ZZZFunApp());
      unawaited(WebServerService.startServer());
    },
    (error, stackTrace) =>
        AppLogger.error('runtime', '未捕获的运行时异常', error, stackTrace),
  );
}

class ZZZFunApp extends StatelessWidget {
  const ZZZFunApp({super.key});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFFFA116);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ZZZFun',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0E1014),
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
          surface: const Color(0xFF15181E),
        ),
        fontFamily: 'Microsoft YaHei',
        useMaterial3: true,
        splashFactory: NoSplash.splashFactory,
        dividerColor: const Color(0xFF292D35),
      ),
      home: const TvHomePage(),
    );
  }
}
