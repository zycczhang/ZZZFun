


<div align=center>

<h1>ZZZFun</h1>

<img src="assets/icon.webp" width=200></img>

<a href="https://t.me/kazumi_app"><img src="https://img.shields.io/badge/Telegram-2CA5E0?style=for-the-badge&logo=telegram&logoColor=white"></img></a>

<img src="https://img.shields.io/badge/Flutter-03A9F4?style=for-the-badge&logo=flutter&logoColor=white"></img>
<img src="https://img.shields.io/badge/Dart-00B4AB?style=for-the-badge&logo=Dart&logoColor=white"></img>

<p>这是一个基于 Flutter 开发的追番看番平台，专为 Android TV 和 投影仪 等大屏设备设计。项目完全适配遥控器操作，拥有流畅的焦点动画以及完善的播放体验</p>
</div>

## 屏幕截图
![示例](assets/1.webp)
![示例](assets/2.webp)
## 当前功能

- 首页展示当前季度热门番剧，按 Bangumi 热度排序
- 日期表展示周一至周日的放送内容
- Bangumi 番剧元数据、评分、简介、海报和剧集信息解析
- 首页海报轮播，支持键盘、遥控器方向键切换
- 本地收藏和观看历史，使用 `SharedPreferences` 持久化保存
- 网络海报使用内存和磁盘缓存，减少重复加载
- 设置页查看应用状态和运行日志
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
    ├── anime_storage_service.dart # 收藏和历史持久化
    └── app_logger.dart             # 日志服务
test/
└── bangumi_api_service_test.dart  # API 解析和请求测试
```

## 免责声明

本项目是完全开源的 Flutter 应用重构项目，仅用于软件开发和界面研究。使用第三方数据服务时，请遵守当地法律法规以及相关服务的使用条款。项目本身不提供视频资源或播放地址。
