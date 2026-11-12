import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class DriverService {

  // لیست IPهای ممکن برای تست
  static const List<String> baseUrls = [
    'http://10.189.102.187:5000/api/driver-app',  // IP ثابت لپ‌تاپ
    'http://192.168.43.1:5000/api/driver-app',   // IP هات‌اسپات اندروید
    'http://192.168.137.1:5000/api/driver-app',  // IP هات‌اسپات ویندوز
    'http://localhost:5000/api/driver-app',       // برای تست روی کامپیوتر
  ];

  static String _activeBaseUrl = baseUrls.first;

  static String get baseUrl => _activeBaseUrl;

  static const String baseUrl = 'http://10.189.102.187:5000/api/driver-app';


  static const Duration _timeout = Duration(seconds: 20);

  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  // ============================================================
  // FIND ACTIVE SERVER
  // ============================================================

  static Future<bool> findActiveServer() async {
    for (final url in baseUrls) {
      try {
        final response = await http.get(
          Uri.parse('$url/health'),
        ).timeout(const Duration(seconds: 3));

        if (response.statusCode == 200) {
          _activeBaseUrl = url;
          debugPrint('ACTIVE SERVER FOUND: $url');
          return true;
        }
      } catch (e) {
        debugPrint('SERVER TEST FAILED: $url');
      }
    }
    return false;
  }

  // ============================================================
  // HELPERS
  // ============================================================

  static Map<String, dynamic> _decodeResponse(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);

      if (decoded is Map<String, dynamic>) {
        return {...decoded, 'httpStatus': response.statusCode};
      }

      return {
        'success': false,
        'message': 'پاسخ سرور معتبر نیست',
        'httpStatus': response.statusCode,
      };
    } catch (e) {
      debugPrint('JSON DECODE ERROR: $e');
      debugPrint('RESPONSE BODY: ${response.body}');

      return {
        'success': false,
        'message': 'پاسخ سرور قابل خواندن نیست',
        'httpStatus': response.statusCode,
      };
    }
  }

  static String formatToman(dynamic value) {
    if (value == null) return '۰';
    final number = num.tryParse(value.toString().replaceAll(',', '').trim());
    if (number == null) return value.toString();
    final rounded = number.round();
    final formatted = rounded.abs().toString();
    final buffer = StringBuffer();
    for (int i = 0; i < formatted.length; i++) {
      if (i > 0 && (formatted.length - i) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(formatted[i]);
    }
    return '${rounded < 0 ? '-' : ''}${buffer.toString()}';
  }

  static Map<String, dynamic> _errorResult(String logTitle, Object error, String message) {
    debugPrint('$logTitle: $error');
    return {'success': false, 'message': '$message: $error'};
  }

  // ============================================================
  // LOGIN
  // ============================================================

  static Future<Map<String, dynamic>> login({
    required String mobile,
    required String password,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/login'),
            headers: _headers,
            body: jsonEncode({'mobile': mobile, 'password': password}),
          )
          .timeout(_timeout);

      return _decodeResponse(response);
    } catch (e) {
      return _errorResult('LOGIN ERROR', e, 'خطا در اتصال به سرور');
    }
  }

  // ============================================================
  // WALLET
  // ============================================================

  static Future<Map<String, dynamic>> getWallet(String driverId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/wallet/$driverId'), headers: _headers)
          .timeout(_timeout);
      return _decodeResponse(response);
    } catch (e) {
      return _errorResult('WALLET ERROR', e, 'خطا در دریافت کیف پول');
    }
  }

  // ============================================================
  // SHEBA
  // ============================================================

  static Future<Map<String, dynamic>> getSheba(String driverId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/sheba/$driverId'), headers: _headers)
          .timeout(_timeout);
      return _decodeResponse(response);
    } catch (e) {
      return _errorResult('GET SHEBA ERROR', e, 'خطا در دریافت اطلاعات شبا');
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
      final response = await http
          .post(
            Uri.parse('$baseUrl/sheba'),
            headers: _headers,
            body: jsonEncode({
              'driverId': driverId,
              'sheba': sheba,
              'accountHolderName': accountHolderName,
              'nationalId': nationalId,
              'birthDate': birthDate,
            }),
          )
          .timeout(_timeout);
      return _decodeResponse(response);
    } catch (e) {
      return _errorResult('SAVE SHEBA ERROR', e, 'خطا در ذخیره اطلاعات شبا');
    }
  }

  // ============================================================
  // DRIVER LOCATION
  // ============================================================

  static Future<bool> updateLocation({
    required String driverId,
    required double lat,
    required double lng,
    required bool isAvailable,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/location'),
            headers: _headers,
            body: jsonEncode({
              'driverId': driverId,
              'lat': lat,
              'lng': lng,
              'isAvailable': isAvailable,
            }),
          )
          .timeout(_timeout);

      final data = _decodeResponse(response);

      return response.statusCode >= 200 &&
          response.statusCode < 300 &&
          data['success'] == true;
    } catch (e) {
      debugPrint('LOCATION UPDATE ERROR: $e');
      return false;
    }
  }

  // ============================================================
  // OFFERS
  // ============================================================

  static Future<List<dynamic>> getOffers(String driverId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/offers/$driverId'), headers: _headers)
          .timeout(_timeout);

      final data = _decodeResponse(response);

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          data['success'] == true &&
          data['offers'] is List) {
        return data['offers'] as List<dynamic>;
      }

      return [];
    } catch (e) {
      debugPrint('GET OFFERS ERROR: $e');
      return [];
    }
  }

  // ============================================================
  // RESPOND TO OFFER
  // ============================================================

  static Future<Map<String, dynamic>> respondToOffer({
    required String offerId,
    required String driverId,
    required String action,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/offers/$offerId/respond'),
            headers: _headers,
            body: jsonEncode({'driverId': driverId, 'action': action}),
          )
          .timeout(_timeout);
      return _decodeResponse(response);
    } catch (e) {
      return _errorResult('RESPOND OFFER ERROR', e, 'خطا در ارتباط با سرور');
    }
  }

  // ============================================================
  // UPDATE ORDER STATUS
  // ============================================================

  static Future<Map<String, dynamic>> updateOrderStatus({
    required String orderId,
    required String driverId,
    required String action,
    String? destId,
    double? lat,
    double? lng,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/orders/$orderId/status'),
            headers: _headers,
            body: jsonEncode({
              'driverId': driverId,
              'action': action,
              if (destId != null) 'destId': destId,
              if (lat != null) 'lat': lat,
              if (lng != null) 'lng': lng,
            }),
          )
          .timeout(_timeout);
      return _decodeResponse(response);
    } catch (e) {
      return _errorResult('UPDATE ORDER STATUS ERROR', e, 'خطا در تغییر وضعیت سفارش');
    }
  }

  // ============================================================
  // POLYGON ARRIVAL RULES
  // ============================================================

  static Future<Map<String, dynamic>?> getPolygonRules({
    required double lat,
    required double lng,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/polygon-rules?lat=$lat&lng=$lng'),
            headers: _headers,
          )
          .timeout(_timeout);

      final data = _decodeResponse(response);

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          data['success'] == true &&
          data['rules'] is Map) {
        return Map<String, dynamic>.from(data['rules'] as Map);
      }
      return null;
    } catch (e) {
      debugPrint('GET POLYGON RULES ERROR: $e');
      return null;
    }
  }

  // ============================================================
  // CANCEL ORDER BY DRIVER
  // ============================================================

  static Future<Map<String, dynamic>> cancelOrderByDriver({
    required String orderId,
    required String driverId,
    String? reason,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/orders/$orderId/cancel-by-driver');
      final response = await http
          .post(
            uri,
            headers: _headers,
            body: jsonEncode({'driverId': driverId, 'reason': reason ?? ''}),
          )
          .timeout(_timeout);

      final data = _decodeResponse(response);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return {
          ...data,
          'success': false,
          'message': data['message'] ?? 'سرور درخواست لغو را نپذیرفت. کد: ${response.statusCode}',
        };
      }
      return data;
    } catch (e) {
      return _errorResult('CANCEL ORDER BY DRIVER ERROR', e, 'ارتباط با سرور برای لغو سفارش برقرار نشد');
    }
  }

  // ============================================================
  // ACTIVE TRIP (تکی، سازگاری)
  // ============================================================

  static Future<Map<String, dynamic>?> getActiveTrip(String driverId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/active-trip/$driverId'), headers: _headers)
          .timeout(_timeout);

      final data = _decodeResponse(response);

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          data['success'] == true &&
          data['order'] is Map) {
        return Map<String, dynamic>.from(data['order'] as Map);
      }
      return null;
    } catch (e) {
      debugPrint('GET ACTIVE TRIP ERROR: $e');
      return null;
    }
  }

  // ============================================================
  // ACTIVE TRIPS (لیست)
  // ============================================================

  static Future<List<Map<String, dynamic>>> getActiveTrips(String driverId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/active-trips/$driverId'), headers: _headers)
          .timeout(_timeout);

      final data = _decodeResponse(response);

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          data['success'] == true &&
          data['orders'] is List) {
        return (data['orders'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('GET ACTIVE TRIPS ERROR: $e');
      return [];
    }
  }

  // ============================================================
  // SINGLE TRIP (برای تازه‌سازی هر ۵ ثانیه)
  // ============================================================

  static Future<Map<String, dynamic>?> getSingleTrip({
    required String driverId,
    required String orderId,
  }) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/active-trip/$driverId/$orderId'), headers: _headers)
          .timeout(_timeout);

      final data = _decodeResponse(response);

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          data['success'] == true &&
          data['order'] is Map) {
        return Map<String, dynamic>.from(data['order'] as Map);
      }
      return null;
    } catch (e) {
      debugPrint('GET SINGLE TRIP ERROR: $e');
      return null;
    }
  }

  // ============================================================
  // REPORT ORDER ISSUE (مرجوع به مبدا)
  // ============================================================

  static Future<Map<String, dynamic>> reportOrderIssue({
    required String orderId,
    required String driverId,
    required String destId,
    required String reason,
    String? note,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/orders/$orderId/report-issue'),
            headers: _headers,
            body: jsonEncode({
              'driverId': driverId,
              'destId': destId,
              'reason': reason,
              if (note != null && note.isNotEmpty) 'note': note,
            }),
          )
          .timeout(_timeout);
      return _decodeResponse(response);
    } catch (e) {
      return _errorResult('REPORT ISSUE ERROR', e, 'خطا در ارتباط با سرور');
    }
  }

  // ============================================================
  // LOG ONLINE STATUS
  // ============================================================

  static Future<bool> logOnlineStatus({
    required String driverId,
    required bool isOnline,
    double? lat,
    double? lng,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/online-status'),
            headers: _headers,
            body: jsonEncode({
              'driverId': driverId,
              'isOnline': isOnline,
              if (lat != null) 'lat': lat,
              if (lng != null) 'lng': lng,
            }),
          )
          .timeout(_timeout);

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('LOG ONLINE STATUS ERROR: $e');
      return false;
    }
  }

  // ============================================================
  // ORDERS HISTORY
  // ============================================================

  static Future<Map<String, dynamic>> getOrdersHistory({
    required String driverId,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/orders-history/$driverId?page=$page&limit=$limit'),
            headers: _headers,
          )
          .timeout(_timeout);

      final data = _decodeResponse(response);

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          data['success'] == true &&
          data['orders'] is List) {
        return {
          'success': true,
          'orders': (data['orders'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList(),
          'pagination': data['pagination'] ?? {},
        };
      }

      return {
        'success': false,
        'orders': [],
        'pagination': {},
        'message': data['message'] ?? 'خطا',
      };
    } catch (e) {
      debugPrint('GET ORDERS HISTORY ERROR: $e');
      return {
        'success': false,
        'orders': [],
        'pagination': {},
        'message': 'خطا در دریافت تاریخچه: $e',
      };
    }
  }

  // ============================================================
  // HEALTH CHECK
  // ============================================================

  static Future<Map<String, dynamic>> checkHealth() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/health'), headers: _headers)
          .timeout(const Duration(seconds: 8));

      final data = _decodeResponse(response);

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          data['success'] == true) {
        return {'success': true, 'data': data};
      }

      return {
        'success': false,
        'message': 'سرور در دسترس نیست',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'اتصال به سرور برقرار نیست: $e',
      };
    }
  }

  // ============================================================
  // SHIFTS
  // ============================================================

  static Future<Map<String, dynamic>> getAvailableShifts({
    required String driverId,
    required double lat,
    required double lng,
    String? date,
  }) async {
    try {
      final query = {
        'lat': lat.toString(),
        'lng': lng.toString(),
        if (date != null) 'date': date,
      };
      final uri = Uri.parse('$baseUrl/shifts/available/$driverId')
          .replace(queryParameters: query);

      final response = await http.get(uri, headers: _headers).timeout(_timeout);
      return _decodeResponse(response);
    } catch (e) {
      return _errorResult('GET AVAILABLE SHIFTS ERROR', e, 'خطا در دریافت شیفت‌ها');
    }
  }

  static Future<Map<String, dynamic>> takeShift({
    required String driverId,
    required String scheduleId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/shifts/take/$driverId'),
            headers: _headers,
            body: jsonEncode({'scheduleId': scheduleId}),
          )
          .timeout(_timeout);
      return _decodeResponse(response);
    } catch (e) {
      return _errorResult('TAKE SHIFT ERROR', e, 'خطا در گرفتن شیفت');
    }
  }

  static Future<Map<String, dynamic>> getMyShifts({
    required String driverId,
    String? from,
    String? to,
  }) async {
    try {
      final query = {
        if (from != null) 'from': from,
        if (to != null) 'to': to,
      };
      final uri = Uri.parse('$baseUrl/shifts/my/$driverId')
          .replace(queryParameters: query);

      final response = await http.get(uri, headers: _headers).timeout(_timeout);
      return _decodeResponse(response);
    } catch (e) {
      return _errorResult('GET MY SHIFTS ERROR', e, 'خطا در دریافت شیفت‌های من');
    }
  }

  static Future<Map<String, dynamic>> cancelShift({
    required String driverId,
    required String assignmentId,
  }) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/shifts/cancel/$driverId/$assignmentId'),
            headers: _headers,
          )
          .timeout(_timeout);
      return _decodeResponse(response);
    } catch (e) {
      return _errorResult('CANCEL SHIFT ERROR', e, 'خطا در لغو شیفت');
    }
  }

  // ============================================================
  // LOG ONLINE SESSION
  // ============================================================

  static Future<bool> logOnlineSession({
    required String driverId,
    required bool isOnline,
    double? lat,
    double? lng,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/online-log'),
            headers: _headers,
            body: jsonEncode({
              'driverId': driverId,
              'eventType': isOnline ? 'ONLINE' : 'OFFLINE',
              if (lat != null) 'lat': lat,
              if (lng != null) 'lng': lng,
            }),
          )
          .timeout(_timeout);

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('LOG ONLINE SESSION ERROR: $e');
      return false;
    }
  }

  // ============================================================
  // PROFILE
  // ============================================================

  static Future<Map<String, dynamic>> getProfile(String driverId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/profile/$driverId'), headers: _headers)
          .timeout(_timeout);
      return _decodeResponse(response);
    } catch (e) {
      return _errorResult('GET PROFILE ERROR', e, 'خطا در دریافت پروفایل');
    }
  }

  // ============================================================
  // EARNINGS REPORT
  // ============================================================

  static Future<Map<String, dynamic>> getEarningsReport(
    String driverId, {
    String period = 'week',
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/profile/$driverId/earnings?period=$period'),
            headers: _headers,
          )
          .timeout(_timeout);
      return _decodeResponse(response);
    } catch (e) {
      return _errorResult('GET EARNINGS ERROR', e, 'خطا در دریافت گزارش درآمد');
    }
  }

  // =====================================================
  // پیام‌ها
  // =====================================================

  static Future<int> getUnreadMessagesCount(String driverId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/messages/unread-count/$driverId'),
        headers: {"Content-Type": "application/json"},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        return data['unreadCount'] as int? ?? 0;
      }
      return 0;
    } catch (e) {
      debugPrint('GET UNREAD MESSAGES ERROR: $e');
      return 0;
    }
  }

  static Future<List<Map<String, dynamic>>> getMessages(String driverId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/messages/$driverId'),
        headers: {"Content-Type": "application/json"},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        return List<Map<String, dynamic>>.from(data['messages'] ?? []);
      }
      return [];
    } catch (e) {
      debugPrint('GET MESSAGES ERROR: $e');
      return [];
    }
  }

  static Future<bool> markMessageAsRead(String messageId, String driverId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/messages/$messageId/read/$driverId'),
        headers: {"Content-Type": "application/json"},
      );
      final data = jsonDecode(response.body);
      return data['success'] == true;
    } catch (e) {
      debugPrint('MARK MESSAGE AS READ ERROR: $e');
      return false;
    }
  }

}

}
}

