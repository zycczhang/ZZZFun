// services/version_service.dart
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class VersionService {
  static const String remoteUrl = "https://gitee.com/zyc1522416243/zycfun/raw/main/assets/version.json";

  // 1. 只获取本地版本数据
  static Future<Map<String, dynamic>> getLocalVersion() async {
    try {
      String jsonString = await rootBundle.loadString('assets/version.json');
      return jsonDecode(jsonString);
    } catch (e) {
      print("读取本地版本文件失败: $e");
      return {"latestVersion": 0}; // 兜底数据
    }
  }

  // 2. 只获取远程版本数据（返回 null 代表网络请求失败）
  static Future<Map<String, dynamic>?> getRemoteVersion() async {
    try {
      final response = await http.get(Uri.parse(remoteUrl)).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      print("获取远程版本失败: $e");
      return null;
    }
  }
}