import 'package:flutter/material.dart';
import '../services/driver_service.dart';
import '../theme/app_theme.dart';

class OrdersHistoryScreen extends StatefulWidget {
  final String driverId;
  const OrdersHistoryScreen({super.key, required this.driverId});

  @override
  State<OrdersHistoryScreen> createState() => _OrdersHistoryScreenState();
}

class _OrdersHistoryScreenState extends State<OrdersHistoryScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _orders = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await DriverService.getOrdersHistory(
      driverId: widget.driverId,
    );

    if (!mounted) return;

    setState(() {
      _loading = false;
      if (result['success'] == true) {
        _orders = (result['orders'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } else {
        _error = result['message']?.toString() ?? 'خطا در دریافت سفارش‌ها';
      }
    });
  }

  String _formatMoney(num? value) {
    if (value == null) return '۰';
    final rounded = value.round();
    final formatted = rounded.abs().toString();
    final buffer = StringBuffer();
    for (int i = 0; i < formatted.length; i++) {
      if (i > 0 && (formatted.length - i) % 3 == 0) buffer.write(',');
      buffer.write(formatted[i]);
    }
    return '${rounded < 0 ? '-' : ''}${buffer.toString()}';
  }

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

  String _translateStatus(String? status) {
    switch (status) {
      case 'DELIVERED':
        return 'تحویل داده شد';
      case 'RETURNED_TO_ORIGIN':
        return 'مرجوع به مبدأ';
      case 'CANCELLED_BY_DRIVER':
        return 'لغو توسط راننده';
      case 'CANCELLED_BY_CUSTOMER':
        return 'لغو توسط مشتری';
      default:
        return status ?? '';
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'DELIVERED':
        return AppColors.success;
      case 'RETURNED_TO_ORIGIN':
        return Colors.orange;
      case 'CANCELLED_BY_DRIVER':
      case 'CANCELLED_BY_CUSTOMER':
        return AppColors.danger;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('سفارش‌های من',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.primaryYellow),
            onPressed: _fetch,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryYellow))
          : _error != null
              ? _buildError()
              : _orders.isEmpty
                  ? _buildEmpty()
                  : RefreshIndicator(
                      color: AppColors.primaryYellow,
                      onRefresh: _fetch,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _orders.length,
                        itemBuilder: (context, i) {
                          return _buildOrderCard(_orders[i]);
                        },
                      ),
                    ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
          const SizedBox(height: 12),
          Text(_error ?? 'خطای نامشخص',
              style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _fetch,
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryYellow,
                foregroundColor: Colors.black),
            child: const Text('تلاش مجدد'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long, size: 64, color: AppColors.textSecondary),
          SizedBox(height: 12),
          Text('هنوز سفارشی ثبت نشده است',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
        ],
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final status = order['status']?.toString();
    final statusColor = _statusColor(status);
    final totalPrice = (order['totalPrice'] as num?)?.toDouble() ?? 0;
    final deliveredAt = order['deliveredAt']?.toString() ?? order['updatedAt']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openDetail(order),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.local_shipping,
                        color: statusColor, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order['orderCode']?.toString() ?? '-',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _translateStatus(status),
                            style: TextStyle(
                                color: statusColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios,
                      color: Colors.white38, size: 14),
                ],
              ),
              const SizedBox(height: 12),
              _buildInfoRow(
                Icons.payments_outlined,
                'مبلغ سفارش',
                '${_formatMoney(totalPrice)} تومان',
                AppColors.primaryYellow,
              ),
              const SizedBox(height: 6),
              _buildInfoRow(
                Icons.calendar_today_outlined,
                'تاریخ',
                _formatDate(deliveredAt),
                Colors.white60,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, color: color.withValues(alpha: 0.7), size: 14),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        const Spacer(),
        Flexible(
          child: Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  void _openDetail(Map<String, dynamic> order) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _OrderDetailScreen(order: order),
      ),
    );
  }
}

// =====================================================
// صفحه جزئیات سفارش
// =====================================================

class _OrderDetailScreen extends StatelessWidget {
  final Map<String, dynamic> order;
  const _OrderDetailScreen({required this.order});

  String _formatMoney(num? value) {
    if (value == null) return '۰';
    final rounded = value.round();
    final formatted = rounded.abs().toString();
    final buffer = StringBuffer();
    for (int i = 0; i < formatted.length; i++) {
      if (i > 0 && (formatted.length - i) % 3 == 0) buffer.write(',');
      buffer.write(formatted[i]);
    }
    return '${rounded < 0 ? '-' : ''}${buffer.toString()}';
  }

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

  String _translateStatus(String? status) {
    switch (status) {
      case 'DELIVERED':
        return 'تحویل داده شد';
      case 'RETURNED_TO_ORIGIN':
        return 'مرجوع به مبدأ';
      case 'CANCELLED_BY_DRIVER':
        return 'لغو توسط راننده';
      case 'CANCELLED_BY_CUSTOMER':
        return 'لغو توسط مشتری';
      default:
        return status ?? '';
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'DELIVERED':
        return AppColors.success;
      case 'RETURNED_TO_ORIGIN':
        return Colors.orange;
      default:
        return AppColors.danger;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = order['status']?.toString();
    final statusColor = _statusColor(status);

    final totalPrice = (order['totalPrice'] as num?)?.toDouble() ?? 0;
    final commissionPercent = (order['commissionPercent'] as num?)?.toDouble() ?? 0;
    final commissionAmount = (order['commissionAmount'] as num?)?.toDouble() ?? 0;
    final municipalTaxPercent = (order['municipalTaxPercent'] as num?)?.toDouble() ?? 0;
    final municipalTaxAmount = (order['municipalTaxAmount'] as num?)?.toDouble() ?? 0;
    final earning = (order['earning'] as num?)?.toDouble() ?? 0;
    final isOnlinePayment = order['isOnlinePayment'] == true;

    final originAddress = order['originAddress']?.toString() ?? '';
    final destinations = (order['destinations'] as List?) ?? [];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(order['orderCode']?.toString() ?? 'جزئیات سفارش',
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.white, fontSize: 15)),
        centerTitle: true,
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ===== وضعیت =====
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: statusColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: statusColor, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _translateStatus(status),
                      style: TextStyle(
                          color: statusColor,
                          fontSize: 14,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ===== مسیر =====
            _buildSection(
              title: 'مسیر سفر',
              icon: Icons.route,
              children: [
                _buildAddressCard(
                  title: 'مبدأ',
                  address: originAddress,
                  color: Colors.green,
                  icon: Icons.trip_origin,
                ),
                const SizedBox(height: 8),
                ...destinations.asMap().entries.map((entry) {
                  final i = entry.key;
                  final d = Map<String, dynamic>.from(entry.value as Map);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildAddressCard(
                      title: 'مقصد ${i + 1}',
                      address: d['address']?.toString() ?? '',
                      color: Colors.red,
                      icon: Icons.location_on,
                    ),
                  );
                }),
              ],
            ),

            const SizedBox(height: 16),

            // ===== مالی =====
            _buildSection(
              title: 'جزئیات مالی',
              icon: Icons.account_balance_wallet,
              children: [
                _buildMoneyRow(
                  label: 'مبلغ کل سفارش',
                  value: '${_formatMoney(totalPrice)} تومان',
                  color: Colors.white,
                  bold: true,
                ),
                const Divider(color: Colors.white12, height: 20),
                _buildMoneyRow(
                  label: 'کمیسیون (${commissionPercent.toStringAsFixed(1)}%)',
                  value: '- ${_formatMoney(commissionAmount)} تومان',
                  color: AppColors.danger,
                ),
                if (municipalTaxAmount > 0) ...[
                  const SizedBox(height: 8),
                  _buildMoneyRow(
                    label: 'عوارض شهرداری (${municipalTaxPercent.toStringAsFixed(1)}%)',
                    value: '- ${_formatMoney(municipalTaxAmount)} تومان',
                    color: AppColors.danger,
                  ),
                ],
                const Divider(color: Colors.white12, height: 20),
                _buildMoneyRow(
                  label: isOnlinePayment
                      ? 'درآمد واریز به کیف پول'
                      : 'درآمد نقدی (از مشتری)',
                  value: isOnlinePayment
                      ? '+ ${_formatMoney(earning)} تومان'
                      : '+ ${_formatMoney(totalPrice - commissionAmount - municipalTaxAmount)} تومان',
                  color: AppColors.success,
                  bold: true,
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isOnlinePayment
                            ? Icons.credit_card
                            : Icons.payments_outlined,
                        color: AppColors.primaryYellow,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isOnlinePayment
                              ? 'پرداخت آنلاین — مبلغ پس از کسر کمیسیون و عوارض به کیف پول واریز شد.'
                              : 'پرداخت نقدی — کرایه را از مشتری دریافت کردید. کمیسیون و عوارض از کیف پول کسر شد.',
                          style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ===== تراکنش‌های کیف پول مرتبط =====
            if ((order['transactions'] as List?)?.isNotEmpty == true) ...[
              _buildSection(
                title: 'تراکنش‌های کیف پول',
                icon: Icons.receipt_long,
                children: (order['transactions'] as List)
                    .map((t) {
                      final tx = Map<String, dynamic>.from(t as Map);
                      final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
                      final isPos = amount > 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: (isPos
                                        ? AppColors.success
                                        : AppColors.danger)
                                    .withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isPos
                                    ? Icons.add_circle_outline
                                    : Icons.remove_circle_outline,
                                color: isPos
                                    ? AppColors.success
                                    : AppColors.danger,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                tx['description']?.toString() ?? '-',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 11),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${isPos ? '+' : ''}${_formatMoney(amount)}',
                              style: TextStyle(
                                color: isPos
                                    ? AppColors.success
                                    : AppColors.danger,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    })
                    .toList(),
              ),
              const SizedBox(height: 16),
            ],

            // ===== زمان‌ها =====
            _buildSection(
              title: 'زمان‌ها',
              icon: Icons.schedule,
              children: [
                _buildTimeRow('تخصیص', order['assignedAt']?.toString()),
                _buildTimeRow('تحویل گرفته شد', order['pickedUpAt']?.toString()),
                _buildTimeRow('تحویل داده شد', order['deliveredAt']?.toString()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primaryYellow, size: 18),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _buildAddressCard({
    required String title,
    required String address,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 3),
                Text(
                  address.isEmpty ? 'آدرس ثبت نشده' : address,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoneyRow({
    required String label,
    required String value,
    required Color color,
    bool bold = false,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: bold ? 14 : 12,
            fontWeight: bold ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildTimeRow(String label, String? raw) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style:
                    const TextStyle(color: Colors.white70, fontSize: 12)),
          ),
          Text(
            _formatDate(raw),
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
        ],
      ),
    );
  }
}