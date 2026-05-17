import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers/core_providers.dart';

final tagRepositoryProvider = Provider<TagRepository>((ref) {
  return TagRepository(ref.watch(apiClientProvider));
});

class TagRepository {
  const TagRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<List<TagItem>> list() async {
    final result = await _apiClient.get<List<TagItem>>(
      '/tags',
      fromJsonT: (json) {
        if (json is! List) {
          return const <TagItem>[];
        }
        return json.map(TagItem.fromJson).toList();
      },
    );
    return result ?? const [];
  }

  Future<TagItem> create(TagRequest request) async {
    final result = await _apiClient.post<TagItem>(
      '/tags',
      data: request.toJson(),
      fromJsonT: TagItem.fromJson,
    );
    if (result == null) {
      throw const FormatException('创建标签响应为空');
    }
    return result;
  }

  Future<TagItem> update(String id, TagRequest request) async {
    final result = await _apiClient.put<TagItem>(
      '/tags/$id',
      data: request.toJson(),
      fromJsonT: TagItem.fromJson,
    );
    if (result == null) {
      throw const FormatException('保存标签响应为空');
    }
    return result;
  }

  Future<void> delete(String id) async {
    await _apiClient.delete<void>('/tags/$id');
  }
}

class TagItem {
  const TagItem({
    required this.id,
    required this.name,
    this.userId = 0,
    this.color = '#6366F1',
    this.icon = 'label',
    this.isSystem = false,
    this.usedCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final int userId;
  final String name;
  final String color;
  final String icon;
  final bool isSystem;
  final int usedCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get sourceLabel => isSystem ? '系统标签' : '自定义标签';

  factory TagItem.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('标签响应格式不正确');
    }
    final map = json.cast<String, dynamic>();
    return TagItem(
      id: map['id'] as String? ?? '',
      userId: _toInt(map['user_id']),
      name: map['name'] as String? ?? '',
      color: map['color'] as String? ?? '#6366F1',
      icon: map['icon'] as String? ?? 'label',
      isSystem: map['is_system'] as bool? ?? false,
      usedCount: _toInt(map['used_count']),
      createdAt: _toDateTime(map['created_at']),
      updatedAt: _toDateTime(map['updated_at']),
    );
  }
}

class TagRequest {
  const TagRequest({
    required this.name,
    required this.color,
    required this.icon,
  });

  final String name;
  final String color;
  final String icon;

  Map<String, dynamic> toJson() {
    return {'name': name, 'color': color, 'icon': icon};
  }
}

int _toInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime? _toDateTime(Object? value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString());
}
