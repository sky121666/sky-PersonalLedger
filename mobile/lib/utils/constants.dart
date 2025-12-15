class AppColors {
  static const primary = Color(0xFF007AFF);
  static const success = Color(0xFF34C759);
  static const warning = Color(0xFFFF9500);
  static const danger = Color(0xFFFF3B30);
  static const background = Color(0xFFF2F2F7);
  static const cardBackground = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF000000);
  static const textSecondary = Color(0xFF8E8E93);
  static const border = Color(0xFFE5E5EA);
}

class Color {
  final int value;
  const Color(this.value);
}

class ApiConfig {
  static const String baseUrl = 'http://localhost:8080/api/v1';
  static const Duration timeout = Duration(seconds: 10);
}
