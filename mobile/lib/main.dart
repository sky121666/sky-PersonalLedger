import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Android 全屏沉浸式
  if (Platform.isAndroid) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ));
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '个人记账',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6366F1)),
        useMaterial3: true,
      ),
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
    _loadUrl();
  }

  Future<void> _loadUrl() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _serverUrl = prefs.getString('server_url');
      _loading = false;
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
    if (!url.startsWith('http')) url = 'http://$url';
    widget.onSave(url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF3B82F6)]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.account_balance_wallet, size: 40, color: Colors.white),
                ),
                const SizedBox(height: 24),
                const Text('个人记账', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 40),
                TextField(
                  controller: _ctrl,
                  decoration: InputDecoration(
                    labelText: '服务器地址',
                    hintText: '192.168.1.100:8080/path',
                    prefixIcon: const Icon(Icons.link),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  keyboardType: TextInputType.url,
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('连接服务器', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    // macOS / Windows 使用简单配置
    if (Platform.isMacOS || Platform.isWindows) {
      _ctrl = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate(
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (_) => setState(() => _isLoading = false),
        ))
        ..loadRequest(Uri.parse(widget.url));
      return;
    }

    // Android 配置
    final params = AndroidWebViewControllerCreationParams();
    _ctrl = WebViewController.fromPlatformCreationParams(params);
    
    if (_ctrl.platform is AndroidWebViewController) {
      (_ctrl.platform as AndroidWebViewController).setMediaPlaybackRequiresUserGesture(false);
    }

    _ctrl
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _isLoading = true),
        onPageFinished: (_) => setState(() => _isLoading = false),
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _clearCacheAndReload() async {
    setState(() => _isLoading = true);
    await _ctrl.clearCache();
    await _ctrl.clearLocalStorage();
    await _ctrl.loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    // macOS / Windows: 全屏 WebView，按钮右下角
    if (Platform.isMacOS || Platform.isWindows) {
      return Scaffold(
        body: Stack(
          children: [
            WebViewWidget(controller: _ctrl),
            if (_isLoading)
              const Positioned(
                top: 0, left: 0, right: 0,
                child: LinearProgressIndicator(
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                ),
              ),
            Positioned(
              right: 16,
              bottom: 100,
              child: _buildMenuButton(),
            ),
          ],
        ),
      );
    }

    // Android: 带安全区域
    final padding = MediaQuery.of(context).padding;
    final androidParams = AndroidWebViewWidgetCreationParams(
      controller: _ctrl.platform as AndroidWebViewController,
      displayWithHybridComposition: true,
    );

    return Scaffold(
      body: Column(
        children: [
          Container(height: padding.top, color: const Color(0xFF6366F1)),
          Expanded(
            child: Stack(
              children: [
                WebViewWidget.fromPlatformCreationParams(params: androidParams),
                if (_isLoading)
                  const Positioned(
                    top: 0, left: 0, right: 0,
                    child: LinearProgressIndicator(
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                    ),
                  ),
                Positioned(
                  right: 16,
                  bottom: 100,
                  child: _buildMenuButton(),
                ),
              ],
            ),
          ),
          Container(height: padding.bottom, color: Colors.white),
        ],
      ),
    );
  }

  Widget _buildMenuButton() {
    return GestureDetector(
      onTap: _showMenu,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.menu, color: Colors.white, size: 22),
      ),
    );
  }

  void _showMenu() {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('设置'),
        message: Text(widget.url, style: const TextStyle(fontSize: 12)),
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
