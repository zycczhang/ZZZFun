import 'dart:async'; // 必须引入
import 'package:flutter/material.dart';
import 'home_page.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'web_server_service.dart';
import 'package:ZYCFun/HeadlessWeb.dart';
import 'services/anime_api_service.dart';
void main() async {
  // 1. 拦截 Print 的关键代码
  runZoned(
        () async {
      // 这里的代码是在 Zone 内部执行的
      WidgetsFlutterBinding.ensureInitialized();

      await WakelockPlus.enable();
      await AnimeApiService.init();

      runApp(const MyApp());

      Future.delayed(Duration(seconds: 1), () {
        WebServerService.startServer();
        HeadlessWeb.init();
      });

    },
    zoneSpecification: ZoneSpecification(
      // 重写 print 方法
      print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
        // 1. 执行原始的 print (输出到 Android Studio/VSCode 控制台)
        parent.print(zone, line);
        // 2. 发送到 Web Server 的日志缓冲区
        WebServerService.addLog(line);
      },
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        radioTheme: RadioThemeData(
          fillColor: WidgetStateProperty.all(Colors.orange),
        ),
      ),
      home: const TvHomePage(),
    );
  }
}
