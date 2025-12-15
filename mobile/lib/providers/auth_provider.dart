import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();
  
  bool _isLoading = true;
  bool _isLoggedIn = false;
  bool? _initialized;

  bool get isLoading => _isLoading;
  bool get isLoggedIn => _isLoggedIn;
  bool? get initialized => _initialized;

  AuthProvider() {
    _init();
  }

  Future<void> _init() async {
    await _apiService.init();
    _isLoggedIn = _apiService.isLoggedIn;
    
    try {
      final status = await _authService.getStatus();
      _initialized = status['initialized'] ?? false;
    } catch (_) {
      _initialized = false;
    }
    
    _isLoading = false;
    notifyListeners();
  }

  Future<void> checkStatus() async {
    try {
      final status = await _authService.getStatus();
      _initialized = status['initialized'] ?? false;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> login(String password) async {
    await _authService.login(password);
    _isLoggedIn = true;
    notifyListeners();
  }

  Future<void> initUser(String password) async {
    await _authService.init(password);
    _isLoggedIn = true;
    _initialized = true;
    notifyListeners();
  }

  Future<void> logout() async {
    await _authService.logout();
    _isLoggedIn = false;
    notifyListeners();
  }

  Future<void> changePassword(String oldPassword, String newPassword) async {
    await _authService.changePassword(oldPassword, newPassword);
    await logout();
  }
}
