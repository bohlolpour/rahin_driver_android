import 'dart:convert';
import 'package:http/http.dart' as http;

class WalletService {
  static const String baseUrl = 'http://localhost:5000';

  static Future<Map<String, dynamic>?> getWalletData(String driverId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/driver-app/wallet/$driverId'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getSheba(String driverId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/driver-app/sheba/$driverId'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> saveSheba({
    required String driverId,
    required String sheba,
    required String accountHolderName,
    required String nationalId,
    required String birthDate,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/driver-app/sheba'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'driverId': driverId,
          'sheba': sheba,
          'accountHolderName': accountHolderName,
          'nationalId': nationalId,
          'birthDate': birthDate,
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      return {
        'success': response.statusCode == 200 && data['success'] == true,
        'message': data['message'] ?? '',
      };
    } catch (e) {
      return {'success': false, 'message': 'خطا در ارتباط با سرور'};
    }
  }
}