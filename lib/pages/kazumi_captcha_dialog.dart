import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../anime_nav_widgets.dart';
import '../models/kazumi_rule_models.dart';

class KazumiCaptchaDialog extends StatefulWidget {
  final KazumiRule rule;
  final String url;

  const KazumiCaptchaDialog({super.key, required this.rule, required this.url});

  @override
  State<KazumiCaptchaDialog> createState() => _KazumiCaptchaDialogState();
}

class _KazumiCaptchaDialogState extends State<KazumiCaptchaDialog> {
  bool _finishing = false;

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri(widget.url),
      );
      final cookieHeader = cookies
          .map((cookie) => '${cookie.name}=${cookie.value}')
          .join('; ');
      if (mounted) Navigator.of(context).pop(cookieHeader);
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: const Color(0xFF10140F),
      insetPadding: const EdgeInsets.symmetric(horizontal: 70, vertical: 38),
      child: SizedBox(
        width: 900,
        height: 650,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '网页验证',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    widget.rule.name,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri(widget.url),
                  headers: {
                    if (widget.rule.referer.isNotEmpty ||
                        widget.rule.baseUrl != null)
                      'Referer': widget.rule.referer.isNotEmpty
                          ? widget.rule.referer
                          : widget.rule.baseUrl.toString(),
                  },
                ),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  cacheEnabled: true,
                  mediaPlaybackRequiresUserGesture: true,
                  userAgent: widget.rule.userAgent.isEmpty
                      ? null
                      : widget.rule.userAgent,
                ),
                onLoadStop: (controller, _) async {
                  final script = widget.rule.antiCrawler.captchaScript.trim();
                  if (script.isNotEmpty) {
                    await controller.evaluateJavascript(source: script);
                  }
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '请在网页中完成验证，完成后确认。',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.62),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  FocusableWidget(
                    autofocus: true,
                    onTap: _finish,
                    builder: (context, focused) => AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: focused
                            ? theme.colorScheme.primary
                            : Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_finishing)
                            SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: focused ? Colors.black : Colors.white,
                              ),
                            )
                          else
                            Icon(
                              Icons.check,
                              size: 17,
                              color: focused ? Colors.black : Colors.white,
                            ),
                          const SizedBox(width: 7),
                          Text(
                            '验证完成',
                            style: TextStyle(
                              color: focused ? Colors.black : Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
