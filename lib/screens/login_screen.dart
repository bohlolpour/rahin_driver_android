import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../widgets/main_nav.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // تغییر نام کنترلر از user به mobile
  final _mobileController = TextEditingController();
  final _passController = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  static const String _supportPhone = '09940770188';

  @override
  void dispose() {
    _mobileController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final mobile = _mobileController.text.trim();
    final password = _passController.text.trim();

    if (mobile.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('شماره موبایل و رمز عبور را وارد کنید'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() => _loading = true);

    // استفاده از نام پارامتر mobile به جای username
    final result = await AuthService.login(mobile: mobile, password: password);

    if (!mounted) return;

    if (result.success) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MainNav(driverId: result.driverId ?? ''),
        ),
      );
    } else {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? 'خطا در ورود'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  void _callSupport() {
    Clipboard.setData(const ClipboardData(text: _supportPhone));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('شماره پشتیبانی کپی شد: 09940770188'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // لوگو
                  Center(
                    child: Image.asset(
                      'assets/images/logo_rahin.png',
                      width: 150,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(
                          Icons.directions_car,
                          size: 100,
                          color: AppColors.primaryYellow,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 40),
                  const Text(
                    'ورود راننده',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 30),

                  // فیلد شماره موبایل
                  TextField(
                    controller: _mobileController,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      hintText: 'شماره موبایل',
                      prefixIcon: Icon(Icons.phone, color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // فیلد رمز عبور
                  TextField(
                    controller: _passController,
                    obscureText: _obscure,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'رمز عبور',
                      prefixIcon: const Icon(Icons.lock_outline, color: AppColors.textSecondary),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                          color: AppColors.textSecondary,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),

                  // دکمه ورود
                  ElevatedButton(
                    onPressed: _loading ? null : _login,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const Text(
                            'ورود',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                  const SizedBox(height: 40),

                  // تماس با پشتیبانی
                  GestureDetector(
                    onTap: _callSupport,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.primaryYellow.withValues(alpha: 0.4)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.support_agent, color: AppColors.primaryYellow, size: 22),
                          SizedBox(width: 10),
                          Text(
                            'تماس با پشتیبانی:',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                          ),
                          SizedBox(width: 6),
                          Text(
                            '09940770188',
                            style: TextStyle(
                              color: AppColors.primaryYellow,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}