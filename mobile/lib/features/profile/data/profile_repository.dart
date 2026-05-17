import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers/core_providers.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(apiClientProvider));
});

class ProfileRepository {
  const ProfileRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<UserProfile> getProfile() async {
    final result = await _apiClient.get<UserProfile>(
      '/auth/profile',
      fromJsonT: UserProfile.fromJson,
    );
    if (result == null) {
      throw const FormatException('个人资料响应为空');
    }
    return result;
  }

  Future<UserProfile> updateProfile(UpdateProfileRequest request) async {
    final result = await _apiClient.put<UserProfile>(
      '/auth/profile',
      data: request.toJson(),
      fromJsonT: UserProfile.fromJson,
    );
    if (result == null) {
      throw const FormatException('个人资料保存响应为空');
    }
    return result;
  }
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    required this.createdAt,
    this.nickname = '',
    this.email = '',
    this.avatar = '',
    this.bio = '',
    this.lastLoginAt,
  });

  final int id;
  final String username;
  final String nickname;
  final String email;
  final String avatar;
  final String bio;
  final String createdAt;
  final String? lastLoginAt;

  String get displayName => nickname.isEmpty ? username : nickname;

  factory UserProfile.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('个人资料响应格式不正确');
    }
    final map = json.cast<String, dynamic>();
    return UserProfile(
      id: _toInt(map['id']),
      username: map['username'] as String? ?? '',
      nickname: map['nickname'] as String? ?? '',
      email: map['email'] as String? ?? '',
      avatar: map['avatar'] as String? ?? '',
      bio: map['bio'] as String? ?? '',
      createdAt: map['created_at'] as String? ?? '',
      lastLoginAt: map['last_login_at'] as String?,
    );
  }
}

class UpdateProfileRequest {
  const UpdateProfileRequest({
    required this.nickname,
    required this.email,
    required this.avatar,
    required this.bio,
  });

  final String nickname;
  final String email;
  final String avatar;
  final String bio;

  Map<String, dynamic> toJson() {
    return {'nickname': nickname, 'email': email, 'avatar': avatar, 'bio': bio};
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
