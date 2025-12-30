import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Android 全屏模式：边到边显示，状态栏和导航栏透明覆盖
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '个人记账',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6366F1)), useMaterial3: true),
      darkTheme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6366F1), brightness: Brightness.dark), useMaterial3: true),
      home: const AppEntry(),
    );
  }
}

class AppEntry extends StatefulWidget {
  const AppEntry({super.key});
  @override
  State<AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<AppEntry> {
  String? _serverUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      setState(() { _serverUrl = prefs.getString('server_url'); _loading = false; });
    });
  }

  void _saveUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', url);
    setState(() => _serverUrl = url);
  }

  void _clearUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('server_url');
    setState(() => _serverUrl = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_serverUrl == null) return ConfigScreen(onSave: _saveUrl);
    return WebScreen(url: _serverUrl!, onLogout: _clearUrl);
  }
}


class ConfigScreen extends StatefulWidget {
  final Function(String) onSave;
  const ConfigScreen({super.key, required this.onSave});
  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final _ctrl = TextEditingController();
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _submit() {
    var url = _ctrl.text.trim();
    if (url.isEmpty) return;
    if (!url.startsWith('http')) url = 'https://$url';
    widget.onSave(url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.account_balance_wallet, size: 64, color: Color(0xFF6366F1)),
              const SizedBox(height: 16),
              const Text('个人记账', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 32),
              TextField(
                controller: _ctrl,
                decoration: const InputDecoration(labelText: '服务器地址', hintText: 'example.com:8080', border: OutlineInputBorder()),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white),
                  child: const Text('连接'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WebScreen extends StatefulWidget {
  final String url;
  final VoidCallback onLogout;
  const WebScreen({super.key, required this.url, required this.onLogout});
  @override
  State<WebScreen> createState() => _WebScreenState();
}

class _WebScreenState extends State<WebScreen> {
  late final WebViewController _ctrl;

  @override
  void initState() {
    super.initState();
    final params = WebViewPlatform.instance is WebKitWebViewPlatform
        ? WebKitWebViewControllerCreationParams()
        : const PlatformWebViewControllerCreationParams();
    _ctrl = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(widget.url));
  }

  // 清除 WebView 缓存并重新加载
  Future<void> _clearCacheAndReload() async {
    await _ctrl.clearCache();
    await _ctrl.clearLocalStorage();
    await _ctrl.loadRequest(Uri.parse(widget.url));
  }

  // 计算按钮底部位置，适配不同平台
  double _getBottomPosition(BuildContext context) {
    final padding = MediaQuery.of(context).padding;
    
    // 检测平台
    if (Theme.of(context).platform == TargetPlatform.android) {
      // Android: 底部导航栏上方 100px
      return padding.bottom + 100;
    } else if (Theme.of(context).platform == TargetPlatform.macOS) {
      // macOS: 底部 100px (没有导航栏)
      return 100;
    } else if (Theme.of(context).platform == TargetPlatform.windows) {
      // Windows: 底部 100px
      return 100;
    } else {
      // 其他平台默认
      return padding.bottom + 100;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 获取安全区域边距，自动适配刘海屏、状态栏、底部导航栏
    final padding = MediaQuery.of(context).padding;
    
    return Scaffold(
      body: Column(
        children: [
          // 顶部安全区域（状态栏高度）
          Container(
            height: padding.top,
            color: const Color(0xFF6366F1), // 主题色填充状态栏区域
          ),
          // WebView 主体
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _ctrl),
                // 设置按钮 - 右下角位置，适配不同平台
                Positioned(
                  right: 16,
                  bottom: _getBottomPosition(context),
                  child: GestureDetector(
                    onTap: _showMenu,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.menu, color: Colors.white, size: 24),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 底部安全区域（导航栏高度）
          Container(
            height: padding.bottom,
            color: Colors.white, // 白色填充底部区域
          ),
        ],
      ),
    );
  }

  void _showMenu() {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('设置'),
        message: Text(widget.url),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () { Navigator.pop(ctx); _ctrl.reload(); },
            child: const Text('刷新页面'),
          ),
          CupertinoActionSheetAction(
            onPressed: () { Navigator.pop(ctx); _clearCacheAndReload(); },
            child: const Text('清除缓存并刷新'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () { Navigator.pop(ctx); widget.onLogout(); },
            child: const Text('更换服务器'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
      ),
    );
  }
}
