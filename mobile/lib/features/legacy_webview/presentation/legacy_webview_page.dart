import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

class LegacyWebViewPage extends StatefulWidget {
  const LegacyWebViewPage({super.key, this.initialUrl});

  final String? initialUrl;

  @override
  State<LegacyWebViewPage> createState() => _LegacyWebViewPageState();
}

class _LegacyWebViewPageState extends State<LegacyWebViewPage> {
  late final TextEditingController _urlController;
  WebViewController? _webViewController;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialUrl ?? '');
    final initialUrl = _normalizeUrl(widget.initialUrl ?? '');
    if (initialUrl != null) {
      _webViewController = _createController(initialUrl);
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  WebViewController _createController(String url) {
    final params = WebViewPlatform.instance is WebKitWebViewPlatform
        ? WebKitWebViewControllerCreationParams()
        : const PlatformWebViewControllerCreationParams();
    return WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(url));
  }

  void _loadUrl() {
    final normalizedUrl = _normalizeUrl(_urlController.text);
    if (normalizedUrl == null) {
      return;
    }
    setState(() {
      _webViewController = _createController(normalizedUrl);
    });
  }

  Future<void> _clearCacheAndReload() async {
    final controller = _webViewController;
    if (controller == null) {
      return;
    }
    await controller.clearCache();
    await controller.clearLocalStorage();
    await controller.reload();
  }

  String? _normalizeUrl(String value) {
    final trimmedValue = value.trim();
    if (trimmedValue.isEmpty) {
      return null;
    }
    if (trimmedValue.startsWith('http://') ||
        trimmedValue.startsWith('https://')) {
      return trimmedValue;
    }
    return 'https://$trimmedValue';
  }

  double _getMenuBottomPosition(BuildContext context) {
    final padding = MediaQuery.of(context).padding;
    if (Theme.of(context).platform == TargetPlatform.android) {
      return padding.bottom + 100;
    }
    return padding.bottom + 32;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _webViewController;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Legacy WebView'),
        actions: [
          IconButton(onPressed: _showMenu, icon: const Icon(Icons.more_vert)),
        ],
      ),
      body: SafeArea(
        child: controller == null
            ? _buildUrlInput(context)
            : _buildWebView(context, controller),
      ),
    );
  }

  Widget _buildUrlInput(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.public,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('低频功能兜底页', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 24),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Web 地址',
                hintText: 'example.com:8080',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _loadUrl(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: _loadUrl, child: const Text('打开')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebView(BuildContext context, WebViewController controller) {
    return Stack(
      children: [
        WebViewWidget(controller: controller),
        Positioned(
          right: 16,
          bottom: _getMenuBottomPosition(context),
          child: FloatingActionButton.small(
            onPressed: _showMenu,
            child: const Icon(Icons.menu),
          ),
        ),
      ],
    );
  }

  void _showMenu() {
    final controller = _webViewController;
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Legacy WebView 设置'),
        message: Text(
          _urlController.text.trim().isEmpty
              ? '未设置地址'
              : _urlController.text.trim(),
        ),
        actions: [
          if (controller != null) ...[
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(context);
                controller.reload();
              },
              child: const Text('刷新页面'),
            ),
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(context);
                _clearCacheAndReload();
              },
              child: const Text('清除缓存并刷新'),
            ),
          ],
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _webViewController = null;
              });
            },
            child: const Text('更换地址'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }
}
