import 'package:geolocator/geolocator.dart';

class LocationService {
  /// دریافت موقعیت فعلی با مدیریت کامل مجوزها
  // در location_service.dart
static Future<Position?> getCurrentPosition() async {
  try {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }
    if (permission == LocationPermission.deniedForever) return null;

    // استفاده از LocationSettings
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      timeLimit: Duration(seconds: 15), // اینجا timeLimit داخل settings است
    );

    try {
      return await Geolocator.getCurrentPosition(locationSettings: settings);
    } catch (_) {
      // اگر تایم‌اوت شد، آخرین موقعیت شناخته‌شده را برگردان
      return await Geolocator.getLastKnownPosition();
    }
  } catch (_) {
    return null;
  }
}

  /// بررسی اینکه مجوزها OK هستن یا نه (بدون درخواست)
  static Future<bool> hasPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }
}