import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class IncentivesScreen extends StatelessWidget {
  const IncentivesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('طرح‌های تشویقی')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _incentiveCard(
            'طرح پیک طلایی',
            'با ۵۰ سفارش در هفته، ۵۰۰,۰۰۰ تومان جایزه بگیر',
            Icons.emoji_events,
            0.65,
          ),
          _incentiveCard(
            'ساعت طلایی',
            'از ۱۸ تا ۲۲ هر سفارش ۲۰٪ بیشتر',
            Icons.access_time,
            0.30,
          ),
          _incentiveCard(
            'دعوت از دوستان',
            'هر راننده جدید ۱۰۰,۰۰۰ تومان',
            Icons.people,
            0.10,
          ),
        ],
      ),
    );
  }

  Widget _incentiveCard(
      String title, String desc, IconData icon, double progress) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primaryYellow.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primaryYellow, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            desc,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: AppColors.card,
              valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.primaryYellow),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${(progress * 100).toInt()}٪ تکمیل شده',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}