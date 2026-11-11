import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('گزارشات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _statCard('درآمد امروز', '۱۲۰,۰۰۰ ت', Icons.today, AppColors.success),
          _statCard('درآمد این هفته', '۸۵۰,۰۰۰ ت', Icons.date_range,
              AppColors.primaryYellow),
          _statCard('درآمد این ماه', '۳,۲۰۰,۰۰۰ ت', Icons.calendar_month,
              AppColors.primaryYellow),
          _statCard('تعداد سفارشات', '۱۴۲', Icons.local_shipping,
              AppColors.success),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.card),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}