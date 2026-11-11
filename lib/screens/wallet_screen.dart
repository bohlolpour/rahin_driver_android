import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/wallet_service.dart';

class WalletScreen extends StatefulWidget {
  final String driverId;
  const WalletScreen({super.key, required this.driverId});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  bool _isLoading = true;
  double _balance = 0;
  List<dynamic> _transactions = [];
  String? _sheba;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    final walletData = await WalletService.getWalletData(widget.driverId);
    final shebaData = await WalletService.getSheba(widget.driverId);

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (walletData != null && walletData['success'] == true) {
          _balance = double.tryParse(walletData['balance'].toString()) ?? 0;
          _transactions = walletData['transactions'] ?? [];
        }
        if (shebaData != null && shebaData['success'] == true) {
          _sheba = shebaData['sheba'];
        }
      });
    }
  }

  // ============================================
  // فرمت اعداد با جداکننده سه‌رقمی
  // ============================================
  String _formatMoney(num? value) {
    if (value == null) return '۰';
    final rounded = value.round();
    final formatted = rounded.abs().toString();
    final buffer = StringBuffer();

    for (int i = 0; i < formatted.length; i++) {
      if (i > 0 && (formatted.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(formatted[i]);
    }

    return '${rounded < 0 ? '-' : ''}${buffer.toString()}';
  }

  // ============================================
  // ترجمه نوع تراکنش
  // ============================================
  String _translateType(String? type) {
    switch (type) {
      case 'MANUAL_CREDIT':
        return 'افزایش دستی';
      case 'MANUAL_DEBIT':
        return 'کسر دستی';
      case 'ORDER_EARNING':
      case 'TRIP_EARNING':
        return 'درآمد سفر';
      case 'ORDER_COMMISSION':
      case 'COMMISSION':
        return 'کمیسیون سفر';
      case 'MUNICIPAL_TAX':
        return 'عوارض شهرداری';
      case 'CHARGE':
        return 'شارژ کیف پول';
      case 'WITHDRAW':
        return 'برداشت';
      case 'REFUND':
        return 'بازگشت وجه';
      case 'GUARANTEE':
        return 'ضمانت';
      case 'RETURN_TO_ORIGIN':
        return 'بازگشت به مبدا';
      case 'RETURN_DEDUCTION':
        return 'کسر مرجوعی';
      default:
        return 'تراکنش';
    }
  }

  // ============================================
  // آیکون و رنگ بر اساس نوع تراکنش
  // ============================================
  IconData _iconForType(String? type) {
    switch (type) {
      case 'MANUAL_CREDIT':
        return Icons.card_giftcard;
      case 'MANUAL_DEBIT':
        return Icons.remove_circle_outline;
      case 'ORDER_EARNING':
      case 'TRIP_EARNING':
        return Icons.account_balance_wallet;
      case 'ORDER_COMMISSION':
      case 'COMMISSION':
        return Icons.percent;
      case 'MUNICIPAL_TAX':
        return Icons.account_balance;
      case 'CHARGE':
        return Icons.add_circle_outline;
      case 'WITHDRAW':
        return Icons.arrow_downward;
      case 'REFUND':
        return Icons.replay;
      case 'GUARANTEE':
        return Icons.verified_user;
      case 'RETURN_TO_ORIGIN':
        return Icons.undo;
      default:
        return Icons.receipt_long;
    }
  }

  // ============================================
  // فرمت تاریخ خوانا
  // ============================================
  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final y = dt.year;
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return '$y/$m/$d - $hh:$mm';
    } catch (_) {
      return raw;
    }
  }

  void _showWithdrawMessage() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('درخواست برداشت',
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        content: const Text(
          'تسویه حساب شما به صورت روزانه انجام می‌شود. در صورت داشتن شماره شبا فعال، کارکردهای شما بر اساس چرخه انتقال پایا به حساب بانکی معرفی‌شده واریز می‌گردد.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.7),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('متوجه شدم',
                style: TextStyle(color: AppColors.primaryYellow, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _openShebaDialog() async {
    final shebaData = await WalletService.getSheba(widget.driverId);

    if (!mounted) return;

    final shebaController = TextEditingController(
        text: shebaData?['sheba']?.toString().replaceFirst('IR', '') ?? '');
    final holderController =
        TextEditingController(text: shebaData?['accountHolderName']?.toString() ?? '');
    final nationalIdController =
        TextEditingController(text: shebaData?['nationalId']?.toString() ?? '');
    final birthDateController =
        TextEditingController(text: shebaData?['birthDate']?.toString() ?? '');

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          bool isSaving = false;

          return AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(
              _sheba == null ? 'ثبت شماره شبا' : 'ویرایش شماره شبا',
              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: shebaController,
                    keyboardType: TextInputType.number,
                    maxLength: 24,
                    textAlign: TextAlign.left,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      letterSpacing: 1,
                      fontSize: 14,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'شماره شبا',
                      hintStyle: TextStyle(color: AppColors.textSecondary),
                      suffixText: 'IR',
                      suffixStyle: TextStyle(
                        color: AppColors.primaryYellow,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      counterStyle: TextStyle(color: AppColors.textSecondary),
                      suffixIcon: Icon(Icons.account_balance, color: AppColors.primaryYellow),
                    ),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: holderController,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      hintText: 'نام کامل صاحب حساب',
                      hintStyle: TextStyle(color: AppColors.textSecondary),
                      prefixIcon: Icon(Icons.person, color: AppColors.primaryYellow),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nationalIdController,
                    keyboardType: TextInputType.number,
                    maxLength: 10,
                    style: const TextStyle(color: AppColors.textPrimary, letterSpacing: 1),
                    decoration: const InputDecoration(
                      hintText: 'کد ملی صاحب حساب',
                      hintStyle: TextStyle(color: AppColors.textSecondary),
                      counterStyle: TextStyle(color: AppColors.textSecondary),
                      prefixIcon: Icon(Icons.badge, color: AppColors.primaryYellow),
                    ),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: birthDateController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: AppColors.textPrimary, letterSpacing: 1),
                    decoration: const InputDecoration(
                      hintText: 'تاریخ تولد (مثال: 1380/08/18)',
                      hintStyle: TextStyle(color: AppColors.textSecondary),
                      prefixIcon: Icon(Icons.cake, color: AppColors.primaryYellow),
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(8),
                      BirthDateInputFormatter(),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'توجه: اطلاعات وارد شده باید با اطلاعات هویتی صاحب حساب در بانک مطابقت داشته باشد.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.6),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(context),
                child: const Text('انصراف',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        final shebaDigits = shebaController.text.trim();
                        final holder = holderController.text.trim();
                        final nationalId = nationalIdController.text.trim();
                        final birthDate = birthDateController.text.trim();

                        if (shebaDigits.length != 24) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('شماره شبا باید دقیقاً ۲۴ رقم باشد'),
                              backgroundColor: AppColors.danger,
                            ),
                          );
                          return;
                        }

                        if (holder.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('نام صاحب حساب را وارد کنید'),
                              backgroundColor: AppColors.danger,
                            ),
                          );
                          return;
                        }

                        if (nationalId.length != 10) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('کد ملی باید ۱۰ رقم باشد'),
                              backgroundColor: AppColors.danger,
                            ),
                          );
                          return;
                        }

                        if (!RegExp(r'^\d{4}/\d{2}/\d{2}$').hasMatch(birthDate)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('فرمت تاریخ تولد باید YYYY/MM/DD باشد'),
                              backgroundColor: AppColors.danger,
                            ),
                          );
                          return;
                        }

                        setDialogState(() => isSaving = true);

                        final result = await WalletService.saveSheba(
                          driverId: widget.driverId,
                          sheba: shebaDigits,
                          accountHolderName: holder,
                          nationalId: nationalId,
                          birthDate: birthDate,
                        );

                        if (!mounted) return;

                        Navigator.pop(context);

                        if (result['success'] == true) {
                          setState(() => _sheba = 'IR' + shebaDigits);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('شماره شبا با موفقیت ثبت شد'),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(result['message'] ?? 'خطا در ثبت شبا'),
                              backgroundColor: AppColors.danger,
                            ),
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryYellow,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black),
                      )
                    : const Text('ثبت', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('کیف پول',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryYellow))
          : RefreshIndicator(
              color: AppColors.primaryYellow,
              onRefresh: _fetchData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ===== کارت موجودی =====
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFC107), Color(0xFFE5A800)],
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryYellow.withValues(alpha: 0.35),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'موجودی کیف پول',
                                style: TextStyle(
                                    color: Colors.black87,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600),
                              ),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.account_balance_wallet,
                                    color: Colors.black87, size: 22),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _formatMoney(_balance),
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 34,
                                  fontWeight: FontWeight.bold,
                                  height: 1.0,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Padding(
                                padding: EdgeInsets.only(bottom: 4),
                                child: Text(
                                  'تومان',
                                  style: TextStyle(
                                      color: Colors.black87,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _openShebaDialog,
                                  icon: const Icon(Icons.account_balance,
                                      color: Colors.black, size: 18),
                                  label: Text(
                                    _sheba == null ? 'ثبت شبا' : 'ویرایش شبا',
                                    style: const TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Colors.white.withValues(alpha: 0.55),
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _showWithdrawMessage,
                                  icon: const Icon(Icons.arrow_downward,
                                      color: Colors.white, size: 18),
                                  label: const Text('برداشت',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Colors.black.withValues(alpha: 0.25),
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_sheba != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.verified,
                                      color: Colors.black87, size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    'شبا: $_sheba',
                                    style: const TextStyle(
                                        color: Colors.black87,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Icon(Icons.receipt_long,
                            color: AppColors.primaryYellow, size: 20),
                        const SizedBox(width: 8),
                        const Text('تاریخچه تراکنش‌ها',
                            style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primaryYellow.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${_transactions.length}',
                            style: const TextStyle(
                                color: AppColors.primaryYellow,
                                fontSize: 12,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (_transactions.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(40),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Column(
                          children: [
                            Icon(Icons.receipt_long,
                                color: AppColors.textSecondary, size: 48),
                            SizedBox(height: 12),
                            Text('هنوز تراکنشی ثبت نشده است',
                                style: TextStyle(color: AppColors.textSecondary)),
                          ],
                        ),
                      )
                    else
                      ..._transactions.map((t) {
                        final amount = double.tryParse(t['amount'].toString()) ?? 0;
                        final isPositive = amount > 0;
                        final type = t['type']?.toString();
                        final typeLabel = _translateType(type);

                        return _transactionItem(
                          title: t['title'] ?? 'تراکنش',
                          typeLabel: typeLabel,
                          date: _formatDate(t['date']?.toString()),
                          amount: _formatMoney(amount.abs()),
                          isPositive: isPositive,
                          icon: _iconForType(type),
                          type: type,
                        );
                      }).toList(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _transactionItem({
    required String title,
    required String typeLabel,
    required String date,
    required String amount,
    required bool isPositive,
    required IconData icon,
    String? type,
  }) {
    // رنگ مخصوص هر نوع
    Color accentColor;
    if (type == 'COMMISSION' || type == 'MUNICIPAL_TAX') {
      accentColor = const Color(0xFFEF5B67); // قرمز برای کسر
    } else if (isPositive) {
      accentColor = AppColors.success;
    } else {
      accentColor = AppColors.danger;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // آیکون
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: accentColor.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, color: accentColor, size: 22),
          ),
          const SizedBox(width: 12),

          // عنوان و نوع و تاریخ
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        typeLabel,
                        style: TextStyle(
                            color: accentColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        date,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 10),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // مبلغ
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isPositive ? '+' : '-'} ${amount}',
                style: TextStyle(
                    color: accentColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              const Text(
                'تومان',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =====================================================
// فرمت‌کننده خودکار تاریخ تولد
// =====================================================
class BirthDateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');

    if (digits.isEmpty) {
      return const TextEditingValue(text: '');
    }

    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      buffer.write(digits[i]);
      if (i == 3 || i == 5) {
        buffer.write('/');
      }
    }

    final formatted = buffer.toString();

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}