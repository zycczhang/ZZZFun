import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/video_source_models.dart';

class VideoSourceResolveException implements Exception {
  final String message;
  final Object? cause;

  const VideoSourceResolveException(this.message, {this.cause});

  @override
  String toString() => cause == null
      ? 'VideoSourceResolveException: $message'
      : 'VideoSourceResolveException: $message: $cause';
}

class ResolvedVideoSource {
  final Uri uri;
  final Map<String, String> headers;
  final bool isHls;

  const ResolvedVideoSource({
    required this.uri,
    this.headers = const {},
    this.isHls = false,
  });
}

/// Resolves a Kazumi episode page into the media URL used by the native
/// player. A fresh headless WebView is used for each request so cookies and
/// JavaScript state cannot leak between unrelated sites.
class VideoSourceResolver {
  VideoSourceResolver({this.defaultTimeout = const Duration(seconds: 25)});

  final Duration defaultTimeout;

  Future<ResolvedVideoSource> resolve(
    VideoEpisode episode, {
    Duration? timeout,
    bool? useLegacyParser,
  }) async {
    final directUri = Uri.tryParse(episode.pageUrl);
    if (directUri == null || !directUri.hasScheme) {
      throw const VideoSourceResolveException('播放页地址无效');
    }
    if (_isMediaUrl(directUri.toString())) {
      return ResolvedVideoSource(
        uri: directUri,
        headers: episode.requestHeaders,
        isHls: _isHlsUrl(directUri.toString()),
      );
    }

    final completer = Completer<ResolvedVideoSource>();
    var resolved = false;
    final legacyParser = useLegacyParser ?? episode.useLegacyParser;

    void completeWithUrl(String rawUrl) {
      if (resolved || completer.isCompleted) return;
      final isResponseManifest = rawUrl.startsWith('m3u8:');
      var normalized = _normalizeMediaUrl(
        isResponseManifest ? rawUrl.substring('m3u8:'.length) : rawUrl,
        directUri,
        allowUnknownMedia: isResponseManifest,
      );
      normalized ??= _normalizeMediaUrl(
        _decodeLegacyMediaUrl(rawUrl),
        directUri,
      );
      if (normalized == null) return;
      resolved = true;
      completer.complete(
        ResolvedVideoSource(
          uri: normalized,
          headers: episode.requestHeaders,
          isHls: isResponseManifest || _isHlsUrl(normalized.toString()),
        ),
      );
    }

    final settings = InAppWebViewSettings(
      javaScriptEnabled: true,
      cacheEnabled: true,
      clearCache: false,
      loadsImagesAutomatically: false,
      mediaPlaybackRequiresUserGesture: false,
      useShouldInterceptRequest: true,
      userAgent: episode.requestHeaders['User-Agent'],
    );

    final webView = HeadlessInAppWebView(
      initialSettings: settings,
      onWebViewCreated: (controller) async {
        controller.addJavaScriptHandler(
          handlerName: 'ZZZFunVideoBridge',
          callback: (args) {
            if (args.isNotEmpty) completeWithUrl(args.first.toString());
            return null;
          },
        );
        await controller.addUserScripts(
          userScripts: [
            UserScript(
              source: legacyParser
                  ? _legacyVideoDetectionScript
                  : _videoDetectionScript,
              injectionTime: legacyParser
                  ? UserScriptInjectionTime.AT_DOCUMENT_END
                  : UserScriptInjectionTime.AT_DOCUMENT_START,
              forMainFrameOnly: false,
            ),
          ],
        );
        await controller.loadUrl(
          urlRequest: URLRequest(
            url: WebUri(episode.pageUrl),
            headers: episode.requestHeaders,
          ),
        );
      },
      onLoadResource: (controller, resource) {
        completeWithUrl(resource.url.toString());
      },
      onReceivedError: (controller, request, error) {
        completeWithUrl(request.url.toString());
      },
    );

    try {
      await webView.run();
      return await completer.future.timeout(
        timeout ?? defaultTimeout,
        onTimeout: () => throw VideoSourceResolveException(
          '播放页解析超时',
          cause: timeout ?? defaultTimeout,
        ),
      );
    } finally {
      await webView.dispose();
    }
  }

  static bool _isMediaUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.m3u8') ||
        lower.contains('.mp4') ||
        lower.contains('.m4v') ||
        lower.contains('.webm');
  }

  static bool _isHlsUrl(String url) => url.toLowerCase().contains('.m3u8');

  Uri? _normalizeMediaUrl(
    String rawUrl,
    Uri pageUri, {
    bool allowUnknownMedia = false,
  }) {
    final raw = rawUrl.trim();
    if (raw.isEmpty || raw.startsWith('blob:') || raw.startsWith('data:')) {
      return null;
    }
    final parsed = Uri.tryParse(raw);
    if (parsed == null) return null;
    final resolved = parsed.hasScheme ? parsed : pageUri.resolve(raw);
    if (resolved.scheme != 'http' && resolved.scheme != 'https') return null;
    if (!allowUnknownMedia && !_isMediaUrl(resolved.toString())) return null;
    return resolved;
  }

  String _decodeLegacyMediaUrl(String rawUrl) {
    final decoded = Uri.decodeFull(rawUrl.trim());
    final uri = Uri.tryParse(decoded);
    if (uri == null) return '';
    final mediaPattern = RegExp(
      r'https?://.*?\.(m3u8|mp4)(?:[?#].*)?$',
      caseSensitive: false,
    );
    for (final value in uri.queryParameters.values) {
      if (mediaPattern.hasMatch(value)) return value;
    }
    return '';
  }
}

const _videoDetectionScript = r'''
(function () {
  function report(value, force) {
    if (!value || typeof value !== 'string') return;
    if (value.indexOf('blob:') === 0 || value.indexOf('data:') === 0) return;
    if (!force && !/\.(m3u8|mp4|m4v|webm)(\?|#|$)/i.test(value)) return;
    try {
      window.flutter_inappwebview.callHandler('ZZZFunVideoBridge', value);
    } catch (_) {}
  }

  function scanVideo(video) {
    report(video.getAttribute('src'), false);
    video.querySelectorAll('source').forEach(function (source) {
      report(source.getAttribute('src'), false);
    });
  }

  function scan() {
    document.querySelectorAll('video').forEach(scanVideo);
  }

  var oldFetch = window.fetch;
  if (oldFetch) {
    window.fetch = function () {
      return oldFetch.apply(this, arguments).then(function (response) {
        response.clone().text().then(function (text) {
          if (text.trim().indexOf('#EXTM3U') === 0) {
            report('m3u8:' + response.url, true);
          } else {
            report(response.url, false);
          }
        }).catch(function () { report(response.url, false); });
        return response;
      });
    };
  }

  var oldOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (method, url) {
    report(url, false);
    this.addEventListener('load', function () {
      try {
        if (typeof this.responseText === 'string' &&
            this.responseText.trim().indexOf('#EXTM3U') === 0) {
          report('m3u8:' + url, true);
        }
      } catch (_) {}
    });
    return oldOpen.apply(this, arguments);
  };

  new MutationObserver(function () { scan(); }).observe(document.documentElement, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ['src']
  });
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', scan);
  } else {
    scan();
  }
})();
''';

const _legacyVideoDetectionScript = r'''
(function () {
  function report(value) {
    if (!value || typeof value !== 'string') return;
    if (value.indexOf('googleads') >= 0 ||
        value.indexOf('googlesyndication') >= 0 ||
        value.indexOf('prestrain') >= 0 ||
        value.indexOf('adtrafficquality') >= 0) return;
    try {
      window.flutter_inappwebview.callHandler('ZZZFunVideoBridge', value);
    } catch (_) {}
  }

  function scan() {
    document.querySelectorAll('iframe').forEach(function (iframe) {
      report(iframe.getAttribute('src'));
    });
    document.querySelectorAll('video').forEach(function (video) {
      report(video.getAttribute('src'));
      video.querySelectorAll('source').forEach(function (source) {
        report(source.getAttribute('src'));
      });
    });
  }

  var observer = new MutationObserver(scan);
  function start() {
    scan();
    if (document.documentElement) {
      observer.observe(document.documentElement, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['src']
      });
    }
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start);
  } else {
    start();
  }
})();
''';
