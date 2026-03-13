import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class VersionService {
  static const String remoteUrl = "https://gitee.com/zyc1522416243/zycfun/raw/main/version.json";

  // 获取本地版本
  static Future<Map<String, dynamic>> getLocalVersion() async {
    try {
      String jsonString = await rootBundle.loadString('assets/version.json');
      return jsonDecode(jsonString);
    } catch (e) {
      return {"version": "0"};
    }
  }

  // 检查更新：返回 true 表示有新版本
  static Future<bool> hasUpdate() async {
    try {
      // 1. 获取远程版本
      final response = await http.get(Uri.parse(remoteUrl)).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return false;
      final remoteData = jsonDecode(response.body);

      // 2. 获取本地版本
      final localData = await getLocalVersion();

      // 3. 比较 buildNumber (数字比较最稳妥)
      int remoteVerson = remoteData['latestVersion'] ?? 0;
      int localVerson = localData['latestVersion'] ?? 0;

      return remoteVerson > localVerson;
    } catch (e) {
      print("版本检查失败: $e");
      return false;
    }
  }
}