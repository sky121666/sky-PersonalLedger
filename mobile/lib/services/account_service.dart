import 'api_service.dart';
import '../models/account.dart';

class AccountService {
  final ApiService _api = ApiService();

  Future<AccountListResponse> getList({bool includeArchived = false}) async {
    final response = await _api.get('/accounts', params: {
      'include_archived': includeArchived,
    });
    if (response.data['code'] == 0) {
      return AccountListResponse.fromJson(response.data['data']);
    }
    throw Exception(response.data['message']);
  }

  Future<Account> getById(String id) async {
    final response = await _api.get('/accounts/$id');
    if (response.data['code'] == 0) {
      return Account.fromJson(response.data['data']);
    }
    throw Exception(response.data['message']);
  }

  Future<Account> create(Map<String, dynamic> data) async {
    final response = await _api.post('/accounts', data: data);
    if (response.data['code'] == 0) {
      return Account.fromJson(response.data['data']);
    }
    throw Exception(response.data['message']);
  }

  Future<Account> update(String id, Map<String, dynamic> data) async {
    final response = await _api.put('/accounts/$id', data: data);
    if (response.data['code'] == 0) {
      return Account.fromJson(response.data['data']);
    }
    throw Exception(response.data['message']);
  }

  Future<void> delete(String id) async {
    final response = await _api.delete('/accounts/$id');
    if (response.data['code'] != 0) {
      throw Exception(response.data['message']);
    }
  }

  Future<void> archive(String id, bool isArchived) async {
    final response = await _api.patch('/accounts/$id/archive', data: {
      'is_archived': isArchived,
    });
    if (response.data['code'] != 0) {
      throw Exception(response.data['message']);
    }
  }
}
