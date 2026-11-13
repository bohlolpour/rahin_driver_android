import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static bool _isInitialized = false;

  static const AndroidNotificationChannel _offerChannel =
      AndroidNotificationChannel(
    'rahin_offers',
    'پیشنهادهای سفر',
    description: 'اعلان دریافت پیشنهاد سفر جدید',
    importance: Importance.max,
    playSound: true,
  );

  static Future<void> init() async {
    if (_isInitialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        debugPrint('NOTIFICATION TAPPED: ${response.payload}');
      },
    );

    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_offerChannel);
    await androidPlugin?.requestNotificationsPermission();

    _isInitialized = true;
  }

  /// نمایش اعلان سفارش جدید + پخش صدای سیستمی
  static Future<void> showNewOfferNotification({
    required int notificationId,
    required String orderCode,
    required String originAddress,
    required String destAddress,
    required String price,
    required String orderId,
  }) async {
    await init();

    // پخش صدای سیستمی هشدار (کاربر حتماً متوجه میشه)
    try {
      SystemSound.play(SystemSoundType.alert);
    } catch (_) {}

    final androidDetails = AndroidNotificationDetails(
      _offerChannel.id,
      _offerChannel.name,
      channelDescription: _offerChannel.description,
      importance: Importance.max,
      priority: Priority.max,
      showWhen: true,
      autoCancel: true,
      playSound: true,
      enableVibration: true,
      styleInformation: BigTextStyleInformation(
        'مبدا: $originAddress\nمقصد: $destAddress\nمبلغ: $price تومان',
        contentTitle: 'پیشنهاد سفر جدید 🚗',
        summaryText: 'سفارش #$orderCode',
      ),
    );

    final details = NotificationDetails(android: androidDetails);

    await _localNotifications.show(
      notificationId,
      'پیشنهاد سفر جدید 🚗',
      'سفارش #$orderCode - $price تومان',
      details,
      payload: orderId,
    );
  }

  static Future<void> cancelNotification(int id) async {
    await _localNotifications.cancel(id);
  }

  static Future<void> cancelAll() async {
    await _localNotifications.cancelAll();
  }
}