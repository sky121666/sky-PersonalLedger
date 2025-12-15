import 'api_service.dart';

class AuthService {
  final ApiService _api = ApiService();

  Future<Map<String, dynamic>> getStatus() async {
    final response = await _api.get('/auth/status');
    if (response.data['code'] == 0) {
      return response.data['data'];
    }
    throw Exception(response.data['message']);
  }

  Future<Map<String, dynamic>> init(String password) async {
    final response = await _api.post('/auth/init', data: {'password': password});
    if (response.data['code'] == 0) {
      final data = response.data['data'];
      await _api.saveTokens(data['access_token'], data['refresh_token']);
      return data;
    }
    throw Exception(response.data['message']);
  }

  Future<Map<String, dynamic>> login(String password) async {
    final response = await _api.post('/auth/login', data: {'password': password});
    if (response.data['code'] == 0) {
      final data = response.data['data'];
      await _api.saveTokens(data['access_token'], data['refresh_token']);
      return data;
    }
    throw Exception(response.data['message']);
  }

  Future<void> logout() async {
    try {
      await _api.post('/auth/logout');
    } finally {
      await _api.clearTokens();
    }
  }

  Future<void> changePassword(String oldPassword, String newPassword) async {
    final response = await _api.post('/auth/change-password', data: {
      'old_password': oldPassword,
      'new_password': newPassword,
    });
    if (response.data['code'] != 0) {
      throw Exception(response.data['message']);
    }
  }
}
