import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('سفارش‌ها')),
      body: const Center(
        child: Text('لیست سفارش‌ها به زودی...', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}