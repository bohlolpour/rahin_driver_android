import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static final _audio = AudioPlayer();
  static bool _inited = false;

  static Future<void> init() async {
    if (_inited) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestSoundPermission: true,
      requestBadgePermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    _inited = true;
  }

  static Future<void> requestPermissions() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
  }

  static Future<void> playOfferAlert({String? title, String? body}) async {
    try {
      await _audio.setReleaseMode(ReleaseMode.loop);
      await _audio.play(AssetSource('sounds/offer_alert.mp3'));
      Future.delayed(const Duration(seconds: 6), () => _audio.stop());
    } catch (_) {}

    try {
      if (await Vibration.hasVibrator() == true) {
        Vibration.vibrate(pattern: [0, 500, 300, 500, 300, 500]);
      }
    } catch (_) {}

    const androidDetails = AndroidNotificationDetails(
      'offer_channel',
      'پیشنهاد سفر',
      channelDescription: 'اعلان سفارش جدید راننده',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
      ),
    );
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title ?? 'سفر جدید!',
      body ?? 'یک سفارش جدید برای شما پیشنهاد شد',
      details,
    );
  }

  static Future<void> stopAlert() async {
    try {
      await _audio.stop();
    } catch (_) {}
    await _plugin.cancelAll();
  }
}