


<div align=center>

<h1>ZZZFun</h1>

<img src="assets/icon.webp" width=200></img>

<a href="https://t.me/kazumi_app"><img src="https://img.shields.io/badge/Telegram-2CA5E0?style=for-the-badge&logo=telegram&logoColor=white"></img></a>

<img src="https://img.shields.io/badge/Flutter-03A9F4?style=for-the-badge&logo=flutter&logoColor=white"></img>
<img src="https://img.shields.io/badge/Dart-00B4AB?style=for-the-badge&logo=Dart&logoColor=white"></img>

<p>这是一个基于 Flutter 开发的追番看番平台，专为 Android TV 和 投影仪 等大屏设备设计。项目完全适配遥控器操作，拥有流畅的焦点动画以及完善的播放体验</p>
</div>

## 屏幕截图
<p align="center">
  <img src="assets/1.webp" width="45%" />
  <img src="assets/2.webp" width="45%" />
</p>

<p align="center">
  <img src="assets/3.webp" width="45%" />
  <img src="assets/4.webp" width="45%" />
</p>

<p align="center">
  <img src="assets/5.webp" width="45%" />
  <img src="assets/6.webp" width="45%" />
</p>

## 当前功能

- 首页展示当前季度热门番剧，按 Bangumi 热度排序
- 日期表展示周一至周日的放送内容
- Bangumi 番剧元数据、评分、简介、海报和剧集信息解析
- KazumiRules API Level 8 规则读取、搜索、线路和分集解析
- 多规则播放源检索、别名重试和候选结果选择
- WebView 播放页解析 m3u8/mp4，并使用 `video_player` 播放
- 首页海报轮播，支持键盘、遥控器方向键切换
- 本地收藏和观看历史，使用 `SharedPreferences` 持久化保存
- 网络海报使用内存和磁盘缓存，减少重复加载
- 独立设置页，支持规则管理、外观信息、缓存清理、开发者日志和关于页面
- 日志支持 debug、info、warning、error 等级以及持久化查看
- 适配 Android TV、模拟器、移动设备和桌面窗口布局



## 开发环境

- Flutter SDK 3.10+
- Dart SDK 3.10+
- Android Studio 或其他 Flutter 开发工具

## 开发命令

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

构建 Android Debug APK：

```bash
flutter build apk --debug
```

## 项目结构

```text
lib/
├── home_page.dart                 # 主界面和四个页面
├── anime_nav_widgets.dart         # 导航栏和焦点交互组件
├── models/                        # 本地模型和 Bangumi 模型
└── services/
    ├── bangumi_api_service.dart   # Bangumi 元数据接口
    ├── kazumi_rules_repository.dart # KazumiRules 索引和规则下载
    ├── kazumi_api_rule_engine.dart  # API 规则网络请求和结果解析
    ├── json_path_service.dart       # KazumiRules 使用的 JSONPath 子集
    ├── video_resource_service.dart   # 视频资源层统一入口
    ├── video_source_resolver.dart    # 播放页 WebView 和媒体地址提取
    ├── anime_storage_service.dart # 收藏和历史持久化
    └── app_logger.dart             # 日志服务
test/
├── bangumi_api_service_test.dart       # Bangumi API 解析和请求测试
├── kazumi_api_rule_engine_test.dart    # 规则执行测试
└── kazumi_rules_repository_test.dart   # 规则仓库缓存测试
```

## 免责声明

本项目是完全开源的 Flutter 应用重构项目，仅用于软件开发和界面研究。使用第三方数据服务时，请遵守当地法律法规以及相关服务的使用条款。项目本身不提供视频资源或播放地址。

播放流程是：Bangumi 标题/别名作为关键词，多个 KazumiRules 规则并行检索；用户选择站点返回的候选内容后获取线路和分集；点击具体分集时，WebView 解析播放页中的 m3u8/mp4，最后交给 `video_player`。搜索结果数量只代表站点返回的候选数量，不代表已经完成媒体地址检测。

## 第三方规则

ZZZFun 使用 [Predidit/KazumiRules](https://github.com/Predidit/KazumiRules) 提供的规则文件。规则文件在运行时从公开仓库读取，ZZZFun 自己实现网络请求和 API Level 8 规则解析，不复制 Kazumi 项目的 GPL-3.0 执行代码。KazumiRules 仓库使用 MIT License，相关版权和许可信息见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。规则只描述如何请求第三方网站，规则仓库不代表第三方网站内容或播放地址的授权。
