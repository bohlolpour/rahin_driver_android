import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'services/driver_service.dart'; // 👈 این خط اضافه شد

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // پیدا کردن سرور فعال
  final serverFound = await DriverService.findActiveServer();
  if (!serverFound) {
    debugPrint('NO SERVER FOUND!');
  }
  
  runApp(const RahinApp());
}

class RahinApp extends StatelessWidget {
  const RahinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'راهین راننده',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      locale: const Locale('fa', 'IR'),
      supportedLocales: const [
        Locale('fa', 'IR'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
      },
      home: const SplashScreen(),
    );
  }
}