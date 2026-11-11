import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/driver_service.dart';
import '../theme/app_theme.dart';

class ProfileScreen extends StatefulWidget {
  final String driverId;

  const ProfileScreen({super.key, required this.driverId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _profile;

  String _period = "week";
  Map<String, dynamic>? _earnings;
  bool _earningsLoading = false;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await DriverService.getProfile(widget.driverId);

    if (!mounted) return;

    if (result['success'] == true) {
      setState(() {
        _profile = result['profile'] as Map<String, dynamic>?;
        _loading = false;
      });
      _loadEarnings();
    } else {
      setState(() {
        _error = result['message']?.toString() ?? 'خطا در دریافت پروفایل';
        _loading = false;
      });
    }
  }

  Future<void> _loadEarnings() async {
    setState(() => _earningsLoading = true);

    final result = await DriverService.getEarningsReport(
      widget.driverId,
      period: _period,
    );

    if (!mounted) return;

    setState(() {
      _earningsLoading = false;
      if (result['success'] == true) {
        _earnings = result;
      }
    });
  }

  void _switchPeriod(String period) {
    if (_period == period) return;
    setState(() {
      _period = period;
      _earnings = null;
    });
    _loadEarnings();
  }

  // ============================================================
  // FORMATTERS
  // ============================================================

  String _formatPrice(num? value) {
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

  // تبدیل میلادی به شمسی
  String _toJalali(String? raw) {
    if (raw == null || raw.isEmpty) return '';

    String dateStr = raw;
    // اگه ISO date بود
    if (raw.contains('T')) {
      dateStr = raw.split('T').first;
    } else if (raw.contains(' ')) {
      dateStr = raw.split(' ').first;
    }

    final parts = dateStr.split('-');
    if (parts.length != 3) return raw;

    final gy = int.tryParse(parts[0]);
    final gm = int.tryParse(parts[1]);
    final gd = int.tryParse(parts[2]);

    if (gy == null || gm == null || gd == null) return raw;

    // الگوریتم تبدیل
    const gDaysInMonth = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    int gy2 = (gm > 2) ? (gy + 1) : gy;
    int days = 355666 +
        (365 * gy) +
        ((gy2 + 3) ~/ 4) -
        ((gy2 + 99) ~/ 100) +
        ((gy2 + 399) ~/ 400) +
        gd;

    for (int i = 0; i < gm - 1; i++) {
      days += gDaysInMonth[i];
    }

    int jy = -1595 + (33 * (days ~/ 12053));
    days %= 12053;
    jy += 4 * (days ~/ 1461);
    days %= 1461;

    if (days > 365) {
      jy += (days - 1) ~/ 365;
      days = (days - 1) % 365;
    }

    int jm, jd;
    if (days < 186) {
      jm = 1 + (days ~/ 31);
      jd = 1 + (days % 31);
    } else {
      jm = 7 + ((days - 186) ~/ 30);
      jd = 1 + ((days - 186) % 30);
    }

    return '$jy/${jm.toString().padLeft(2, '0')}/${jd.toString().padLeft(2, '0')}';
  }

  String _formatShortDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final jalali = _toJalali(raw);
    // اگه شمسی خروجی گرفتیم، فقط ماه/روز
    final parts = jalali.split('/');
    if (parts.length == 3) {
      return '${parts[1]}/${parts[2]}';
    }
    return jalali;
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'پروفایل من',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        centerTitle: true,
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primaryYellow,
          indicatorWeight: 3,
          labelColor: AppColors.primaryYellow,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: 'اطلاعات من'),
            Tab(text: 'گزارش درآمد'),
          ],
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryYellow),
            )
          : _error != null
              ? _buildError()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildInfoTab(),
                    _buildEarningsTab(),
                  ],
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.danger, size: 56),
            const SizedBox(height: 12),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _load,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryYellow,
                foregroundColor: Colors.black,
              ),
              child: const Text('تلاش مجدد'),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // INFO TAB
  // ============================================================

  Widget _buildInfoTab() {
    final p = _profile!;
    final vehicle = p['vehicle'] as Map? ?? {};
    final stats = p['stats'] as Map? ?? {};
    final photoUrl = p['profilePhotoUrl']?.toString();

    return RefreshIndicator(
      color: AppColors.primaryYellow,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Hero
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primaryYellow.withValues(alpha: 0.15),
                  AppColors.surface,
                ],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.primaryYellow.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primaryYellow,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 3,
                    ),
                    image: (photoUrl != null && photoUrl.isNotEmpty)
                        ? DecorationImage(
                            image: NetworkImage(
                              '${DriverService.baseUrl.replaceAll('/api/driver-app', '')}$photoUrl',
                            ),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: (photoUrl == null || photoUrl.isEmpty)
                      ? const Icon(
                          Icons.person,
                          color: Colors.black,
                          size: 40,
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p['fullName']?.toString() ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        p['mobile']?.toString() ?? '',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                        textDirection: TextDirection.ltr,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          p['status'] == 'ACTIVE' ? '✓ فعال' : p['status'].toString(),
                          style: const TextStyle(
                            color: AppColors.success,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // آمار
          Row(
            children: [
              Expanded(
                child: _bigStatCard(
                  Icons.inventory_2,
                  'کل سفارش‌ها',
                  _formatPrice(stats['totalOrders']),
                  AppColors.success,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _bigStatCard(
                  Icons.event_available,
                  'شیفت‌های حضور',
                  _formatPrice(stats['totalAttendedShifts']),
                  AppColors.primaryYellow,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          _section(
            title: 'اطلاعات شخصی',
            icon: Icons.badge,
            children: [
              _infoRow('نام', p['firstName']?.toString()),
              _infoRow('نام خانوادگی', p['lastName']?.toString()),
              _infoRow('نام پدر', p['fatherName']?.toString()),
              _infoRow('کد ملی', p['nationalId']?.toString(), ltr: true),
              _infoRow('تاریخ تولد', _toJalali(p['birthDate']?.toString())),
              _infoRow('موبایل', p['mobile']?.toString(), ltr: true),
              _infoRow('ایمیل', p['email']?.toString(), ltr: true),
            ],
          ),

          const SizedBox(height: 12),

          _section(
            title: 'آدرس',
            icon: Icons.location_on,
            children: [
              _infoRow('استان', p['province']?.toString()),
              _infoRow('شهر', p['city']?.toString()),
              _infoRow('خیابان', p['street']?.toString()),
              _infoRow('کد پستی', p['postalCode']?.toString(), ltr: true),
            ],
          ),

          const SizedBox(height: 12),

          _section(
            title: 'اطلاعات خودرو',
            icon: Icons.directions_car,
            children: [
              _infoRow('نوع', vehicle['type']?.toString()),
              _infoRow('برند', vehicle['brand']?.toString()),
              _infoRow('مدل', vehicle['model']?.toString()),
              _infoRow('سال ساخت', vehicle['year']?.toString()),
              _infoRow('رنگ', vehicle['color']?.toString()),
              _infoRow('پلاک', vehicle['plateDisplayLabel']?.toString()),
              _infoRow('شماره بیمه', vehicle['insuranceNumber']?.toString(), ltr: true),
              _infoRow('شرکت بیمه', vehicle['insuranceCompany']?.toString()),
            ],
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _bigStatCard(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _section({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primaryYellow, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _infoRow(String label, String? value, {bool ltr = false}) {
    final hasValue = value != null && value.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: hasValue
                ? Text(
                    value,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
                    textAlign: TextAlign.right,
                  )
                : Text(
                    'ثبت نشده',
                    style: TextStyle(
                      color: AppColors.textSecondary.withValues(alpha: 0.6),
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // EARNINGS TAB
  // ============================================================

  Widget _buildEarningsTab() {
    return RefreshIndicator(
      color: AppColors.primaryYellow,
      onRefresh: _loadEarnings,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Period switch
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Row(
              children: [
                Expanded(child: _periodBtn('week', '۷ روز اخیر')),
                Expanded(child: _periodBtn('month', '۳۰ روز اخیر')),
              ],
            ),
          ),

          const SizedBox(height: 16),

          if (_earningsLoading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                child: CircularProgressIndicator(
                  color: AppColors.primaryYellow,
                ),
              ),
            )
          else if (_earnings == null)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'گزارشی موجود نیست',
                style: TextStyle(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            )
          else
            ..._buildEarningsContent(),
        ],
      ),
    );
  }

  Widget _periodBtn(String period, String label) {
    final isActive = _period == period;
    return GestureDetector(
      onTap: () => _switchPeriod(period),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primaryYellow : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isActive ? Colors.black : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildEarningsContent() {
    final summary = _earnings!['summary'] as Map? ?? {};
    final daily = (_earnings!['daily'] as List?) ?? [];

    final totalEarnings = (summary['totalEarnings'] as num?)?.toInt() ?? 0;
    final totalCommissions = (summary['totalCommissions'] as num?)?.toInt() ?? 0;
    final totalNet = (summary['totalNet'] as num?)?.toInt() ?? 0;
    final totalOrders = (summary['totalOrders'] as num?)?.toInt() ?? 0;

    // فقط روزهایی که درآمد دارن
    final activeDays = daily
        .where((d) {
  final earnings = ((d as Map)['earnings'] as num?)?.toInt() ?? 0;
  return earnings > 0;
})
        .toList();

    final maxEarnings = activeDays.fold<int>(
      0,
      (m, d) {
        final v = ((d as Map)['earnings'] as num?)?.toInt() ?? 0;
        return v > m ? v : m;
      },
    );

    return [
      // کارت اصلی
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primaryYellow.withValues(alpha: 0.2),
              AppColors.surface,
            ],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.primaryYellow.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          children: [
            const Text(
              'درآمد خالص',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_formatPrice(totalNet)} تومان',
              style: const TextStyle(
                color: AppColors.primaryYellow,
                fontSize: 30,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _period == 'week' ? '۷ روز اخیر' : '۳۰ روز اخیر',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),

      const SizedBox(height: 12),

      Row(
        children: [
          Expanded(
            child: _miniStat('درآمد کل', _formatPrice(totalEarnings), AppColors.success),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _miniStat('کمیسیون', _formatPrice(totalCommissions), AppColors.danger),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _miniStat('سفارش‌ها', _formatPrice(totalOrders), AppColors.primaryYellow),
          ),
        ],
      ),

      const SizedBox(height: 20),

      const Text(
        'نمودار درآمد روزانه',
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),

      const SizedBox(height: 4),

      const Text(
        'فقط روزهای دارای درآمد نمایش داده می‌شوند',
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 10,
        ),
      ),

      const SizedBox(height: 12),

      // نمودار
      Container(
        padding: const EdgeInsets.fromLTRB(8, 16, 16, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: activeDays.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                  child: Text(
                    'درآمدی در این بازه ثبت نشده',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              )
            : SizedBox(
                height: 220,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: activeDays.map((d) {
                    final day = d as Map;
                    final earnings =
                        (day['earnings'] as num?)?.toInt() ?? 0;
                    final ratio =
                        maxEarnings > 0 ? earnings / maxEarnings : 0.0;
                    final dateStr = day['date']?.toString() ?? '';
                    final shortDate = _formatShortDate(dateStr);

                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // مقدار بالای میله
                            Text(
                              _formatPrice(earnings),
                              style: const TextStyle(
                                color: AppColors.primaryYellow,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            // میله
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 500),
                              height: (ratio * 140).clamp(20.0, 140.0),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    AppColors.primaryYellow,
                                    AppColors.primaryYellow.withValues(alpha: 0.4),
                                  ],
                                ),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(6),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            // تاریخ زیر میله
                            Text(
                              shortDate,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 9,
                              ),
                              textDirection: TextDirection.ltr,
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
      ),

      const SizedBox(height: 20),

      // لیست روزانه
      const Text(
        'جزئیات روزانه',
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),

      const SizedBox(height: 10),

      if (activeDays.isEmpty)
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'درآمدی در این بازه ثبت نشده',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        )
      else
        ...activeDays.reversed.map((d) {
          final day = d as Map;
          final date = day['date']?.toString() ?? '';
          final earnings = (day['earnings'] as num?)?.toInt() ?? 0;
          final net = (day['net'] as num?)?.toInt() ?? 0;
          final orders = (day['orderCount'] as num?)?.toInt() ?? 0;
          final commission =
              (day['commissions'] as num?)?.toInt() ?? 0;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryYellow.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.calendar_today,
                    color: AppColors.primaryYellow,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _toJalali(date),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$orders سفارش · کمیسیون ${_formatPrice(commission)}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${_formatPrice(net)}',
                      style: TextStyle(
                        color: net >= 0
                            ? AppColors.success
                            : AppColors.danger,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'تومان',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
    ];
  }

  Widget _miniStat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 9,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}