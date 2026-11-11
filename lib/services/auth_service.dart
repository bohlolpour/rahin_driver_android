import 'dart:convert';
import 'package:http/http.dart' as http;

class AuthResult {
  final bool success;
  final String? message;
  final String? token;
  final String? driverId;
  final String? fullName;

  AuthResult({required this.success, this.message, this.token, this.driverId, this.fullName});
}

class AuthService {
  static const String baseUrl = 'http://localhost:5000';

  static Future<AuthResult> login({
    required String mobile,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/driver-app/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'mobile': mobile, 'password': password}),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return AuthResult(
          success: true,
          token: data['token'],
          driverId: data['driverId'].toString(),
          fullName: data['fullName'],
        );
      } else {
        return AuthResult(
          success: false,
          message: data['message'] ?? 'خطا در ورود',
        );
      }
    } catch (e) {
      return AuthResult(success: false, message: 'خطا در ارتباط با سرور');
    }
  }
}