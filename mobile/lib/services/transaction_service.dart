import 'api_service.dart';
import '../models/transaction.dart';

class TransactionService {
  final ApiService _api = ApiService();

  Future<TransactionListResponse> getList({
    int page = 1,
    int pageSize = 20,
    String? startDate,
    String? endDate,
    String? type,
    String? accountId,
    String? categoryId,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'page_size': pageSize,
    };
    if (startDate != null) params['start_date'] = startDate;
    if (endDate != null) params['end_date'] = endDate;
    if (type != null) params['type'] = type;
    if (accountId != null) params['account_id'] = accountId;
    if (categoryId != null) params['category_id'] = categoryId;

    final response = await _api.get('/transactions', params: params);
    if (response.data['code'] == 0) {
      return TransactionListResponse.fromJson(response.data['data']);
    }
    throw Exception(response.data['message']);
  }

  Future<Transaction> getById(String id) async {
    final response = await _api.get('/transactions/$id');
    if (response.data['code'] == 0) {
      return Transaction.fromJson(response.data['data']);
    }
    throw Exception(response.data['message']);
  }

  Future<Transaction> create(Map<String, dynamic> data) async {
    final response = await _api.post('/transactions', data: data);
    if (response.data['code'] == 0) {
      return Transaction.fromJson(response.data['data']);
    }
    throw Exception(response.data['message']);
  }

  Future<Transaction> update(String id, Map<String, dynamic> data) async {
    final response = await _api.put('/transactions/$id', data: data);
    if (response.data['code'] == 0) {
      return Transaction.fromJson(response.data['data']);
    }
    throw Exception(response.data['message']);
  }

  Future<void> delete(String id) async {
    final response = await _api.delete('/transactions/$id');
    if (response.data['code'] != 0) {
      throw Exception(response.data['message']);
    }
  }

  Future<void> batchDelete(List<String> ids) async {
    final response = await _api.post('/transactions/batch-delete', data: {
      'ids': ids,
    });
    if (response.data['code'] != 0) {
      throw Exception(response.data['message']);
    }
  }
}
