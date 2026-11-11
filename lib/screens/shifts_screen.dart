import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/driver_service.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';

class ShiftsScreen extends StatefulWidget {
  final String driverId;
  final double? manualLat;
  final double? manualLng;

  const ShiftsScreen({
    super.key,
    required this.driverId,
    this.manualLat,
    this.manualLng,
  });

  @override
  State<ShiftsScreen> createState() => _ShiftsScreenState();
}

class _ShiftsScreenState extends State<ShiftsScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _statsData;

  late DateTime _baseDate;
  int _selectedDayIndex = 0;

  late AnimationController _pulseController;

  static const _persianWeekDays = [
    'شنبه',
    'یکشنبه',
    'دوشنبه',
    'سه‌شنبه',
    'چهارشنبه',
    'پنجشنبه',
    'جمعه',
  ];

  @override
  void initState() {
    super.initState();
    _baseDate = DateTime.now();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _load();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // ============================================================
  // HELPERS
  // ============================================================

  String _toGregorian(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// تبدیل میلادی به شمسی (الگوریتم استاندارد)
  ({int year, int month, int day}) _toJalaliParts(DateTime d) {
    const gDaysInMonth = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

    int gy = d.year;
    int gm = d.month;
    int gd = d.day;

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

    return (year: jy, month: jm, day: jd);
  }

  String _persianWeekDay(DateTime d) {
    if (d.weekday == 6) return 'شنبه';
    if (d.weekday == 7) return 'یکشنبه';
    return _persianWeekDays[d.weekday - 1];
  }

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  String? _slotStartTime(String slotCode) {
    const slots = {
      '08-09': '08:00',
      '09-11': '09:00',
      '11-14': '11:00',
      '14-17': '14:00',
      '17-20': '17:00',
      '20-22': '20:00',
      '22-24': '22:00',
    };
    return slots[slotCode];
  }

  String _monthName(int month) {
    const names = [
      '',
      'فروردین',
      'اردیبهشت',
      'خرداد',
      'تیر',
      'مرداد',
      'شهریور',
      'مهر',
      'آبان',
      'آذر',
      'دی',
      'بهمن',
      'اسفند',
    ];
    return names[month.clamp(0, 12)];
  }

  // ============================================================
  // DATA LOAD
  // ============================================================

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      double? lat = widget.manualLat;
      double? lng = widget.manualLng;

      if (lat == null || lng == null) {
        final pos = await LocationService.getCurrentPosition();

        if (pos == null) {
          setState(() {
            _loading = false;
            _error = 'موقعیت مکانی در دسترس نیست. GPS را روشن کنید.';
          });
          return;
        }

        lat = pos.latitude;
        lng = pos.longitude;
      }

      final results = await Future.wait([
        DriverService.getAvailableShifts(
          driverId: widget.driverId,
          lat: lat!,
          lng: lng!,
          date: _toGregorian(_baseDate),
        ),
        DriverService.getMyShifts(driverId: widget.driverId),
      ]);

      if (!mounted) return;

      final shiftsResult = results[0];
      final statsResult = results[1];

      if (shiftsResult['success'] != true) {
        setState(() {
          _loading = false;
          _error = shiftsResult['message']?.toString() ?? 'خطا در دریافت شیفت‌ها';
        });
        return;
      }

      setState(() {
        _loading = false;
        _data = shiftsResult;
        if (statsResult['success'] == true) {
          _statsData = statsResult;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'خطا: $e';
      });
    }
  }

  // ============================================================
  // ACTIONS
  // ============================================================

  Future<void> _takeShift(Map<String, dynamic> slot) async {
    final isPaid = slot['isPaid'] == true;
    final price = (slot['price'] as num?)?.toDouble() ?? 0;
    final guarantee = (slot['guaranteeAmount'] as num?)?.toDouble() ?? 0;

    if (isPaid) {
      final confirmed = await _showConfirmDialog(
        title: 'خرید شیفت',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _dialogRow(
              icon: Icons.shopping_cart_outlined,
              label: 'مبلغ قابل پرداخت',
              value: '${DriverService.formatToman(price)} تومان',
              color: AppColors.primaryYellow,
            ),
            if (guarantee > 0) ...[
              const SizedBox(height: 10),
              _dialogRow(
                icon: Icons.verified_outlined,
                label: 'گارانتی تشویقی',
                value: '${DriverService.formatToman(guarantee)} تومان',
                color: AppColors.success,
              ),
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primaryYellow.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primaryYellow.withValues(alpha: 0.2),
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: AppColors.primaryYellow,
                    size: 18,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'در صورت لغو تا قبل از شروع شیفت، ۸۰٪ مبلغ به کیف پول بازمی‌گردد. بعد از شروع شیفت، مبلغی بازنمی‌گردد.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        confirmText: 'تأیید و خرید',
        confirmColor: AppColors.primaryYellow,
      );

      if (confirmed != true) return;
    } else {
      final confirmed = await _showConfirmDialog(
        title: 'گرفتن شیفت',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'این شیفت رایگان است. آیا مطمئن هستید؟',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.7,
              ),
            ),
            if (guarantee > 0) ...[
              const SizedBox(height: 12),
              _dialogRow(
                icon: Icons.verified_outlined,
                label: 'گارانتی تشویقی',
                value: '${DriverService.formatToman(guarantee)} تومان',
                color: AppColors.success,
              ),
            ],
          ],
        ),
        confirmText: 'تأیید',
        confirmColor: AppColors.success,
      );

      if (confirmed != true) return;
    }

    setState(() => _loading = true);

    final result = await DriverService.takeShift(
      driverId: widget.driverId,
      scheduleId: slot['scheduleId'].toString(),
    );

    if (!mounted) return;

    if (result['success'] == true) {
      _showSuccess(result['message']?.toString() ?? 'شیفت گرفته شد');
      await _load();
    } else {
      setState(() => _loading = false);
      _showError(result['message']?.toString() ?? 'خطا');
    }
  }

  Future<void> _cancelShift({
    required String assignmentId,
    required String shiftDate,
    required String shiftSlot,
  }) async {
    final slotStart = _slotStartTime(shiftSlot);
    bool shiftStarted = false;

    if (slotStart != null) {
      final shiftStart = DateTime.parse('${shiftDate}T${slotStart}:00');
      shiftStarted = DateTime.now().isAfter(shiftStart) ||
          DateTime.now().isAtSameMomentAs(shiftStart);
    }

    final confirmed = await _showConfirmDialog(
      title: 'لغو شیفت',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            shiftStarted
                ? 'زمان شروع این شیفت گذشته است.'
                : 'آیا از لغو این شیفت مطمئن هستید؟',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (shiftStarted ? AppColors.danger : Colors.orange)
                  .withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (shiftStarted ? AppColors.danger : Colors.orange)
                    .withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  shiftStarted
                      ? Icons.error_outline_rounded
                      : Icons.warning_amber_rounded,
                  color: shiftStarted ? AppColors.danger : Colors.orange,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    shiftStarted
                        ? 'چون زمان شروع شیفت گذشته، کل مبلغ پرداختی به‌عنوان جریمه کسر می‌شود و مبلغی به کیف پول بازنمی‌گردد.'
                        : '۸۰٪ مبلغ به کیف پول بازمی‌گردد و ۲۰٪ به‌عنوان جریمه کسر می‌شود.',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      height: 1.7,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (shiftStarted) ...[
            const SizedBox(height: 8),
            const Text(
              '⚠️ توجه: در صورت لغو، مبلغ بازگشتی وجود نخواهد داشت.',
              style: TextStyle(
                color: AppColors.danger,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                height: 1.7,
              ),
            ),
          ],
        ],
      ),
      confirmText: shiftStarted ? 'با جریمه کامل لغو کن' : 'لغو شیفت',
      confirmColor: AppColors.danger,
    );

    if (confirmed != true) return;

    setState(() => _loading = true);

    final result = await DriverService.cancelShift(
      driverId: widget.driverId,
      assignmentId: assignmentId,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      _showSuccess(result['message']?.toString() ?? 'لغو شد');
      await _load();
    } else {
      setState(() => _loading = false);
      _showError(result['message']?.toString() ?? 'خطا');
    }
  }

  // ============================================================
  // DIALOG & MESSAGES
  // ============================================================

  Future<bool?> _showConfirmDialog({
    required String title,
    required Widget content,
    required String confirmText,
    required Color confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
        contentPadding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: confirmColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                title.contains('لغو')
                    ? Icons.cancel_outlined
                    : Icons.shopping_cart_checkout,
                color: confirmColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(child: content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text(
              'انصراف',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: Colors.black,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              confirmText,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dialogRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildAppBar(),
            Expanded(
              child: _loading
                  ? _buildLoading()
                  : _error != null
                      ? _buildError()
                      : _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // APPBAR
  // ============================================================

  Widget _buildAppBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            children: [
              _buildIconButton(
                icon: Icons.arrow_back,
                onTap: () => Navigator.pop(context),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'شیفت‌های من',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'مدیریت و خرید شیفت',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _buildIconButton(
                icon: Icons.refresh_rounded,
                onTap: _loading ? null : _load,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  // ============================================================
  // LOADING & ERROR
  // ============================================================

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Transform.scale(
                scale: 0.85 + (_pulseController.value * 0.15),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.primaryYellow.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.calendar_month_rounded,
                    color: AppColors.primaryYellow,
                    size: 40,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.primaryYellow,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'در حال بارگذاری شیفت‌ها...',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                color: AppColors.danger,
                size: 44,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.8,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('تلاش مجدد'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryYellow,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // MAIN CONTENT
  // ============================================================

  Widget _buildContent() {
    final data = _data!;
    final shiftEnabled = data['shiftEnabled'] == true;
    final days = data['days'] as List? ?? [];

    return RefreshIndicator(
      color: AppColors.primaryYellow,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 30),
        children: [
          if (_statsData != null) _buildStatsCard(),

          if (!shiftEnabled)
            _buildDisabledState(data)
          else ...[
            _buildDaysSelector(days),
            const SizedBox(height: 8),
            _buildSlotsList(days),
          ],
        ],
      ),
    );
  }

  Widget _buildDisabledState(Map<String, dynamic> data) {
    final city = data['city'] as Map?;
    final polygon = data['polygon'] as Map?;
    final message =
        data['message']?.toString() ?? 'شیفت برای منطقه شما فعال نیست';

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 30),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.primaryYellow.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.event_busy_rounded,
                    color: AppColors.primaryYellow,
                    size: 44,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    height: 1.7,
                  ),
                ),
                if (city != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_on,
                          color: AppColors.textSecondary,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${city['name'] ?? ''}'
                          '${polygon != null ? ' — ${polygon['name'] ?? ''}' : ''}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // STATS CARD
  // ============================================================

  Widget _buildStatsCard() {
    final stats = _statsData?['stats'] as Map? ?? {};
    final attendanceRate = (stats['attendanceRate'] as num?)?.toInt() ?? 0;
    final successRate = (stats['successRate'] as num?)?.toInt() ?? 0;
    final totalShifts = (stats['totalShifts'] as num?)?.toInt() ?? 0;
    final attendedShifts = (stats['attendedShifts'] as num?)?.toInt() ?? 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryYellow.withValues(alpha: 0.15),
            AppColors.surface,
            AppColors.surface,
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          stops: const [0, 0.5, 1],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primaryYellow.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildStatItem(
              icon: Icons.event_available_rounded,
              label: 'نرخ حضور',
              value: '$attendanceRate٪',
              subLabel: '$attendedShifts از $totalShifts شیفت',
              color: AppColors.success,
            ),
          ),
          Container(
            width: 1,
            height: 60,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.white.withValues(alpha: 0.1),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Expanded(
            child: _buildStatItem(
              icon: Icons.inventory_2_outlined,
              label: 'جمع‌آوری موفق',
              value: '$successRate٪',
              subLabel: '۳۰ روز اخیر',
              color: AppColors.primaryYellow,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required String subLabel,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.bold,
            height: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subLabel,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 9,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // DAYS SELECTOR
  // ============================================================

  Widget _buildDaysSelector(List days) {
    if (days.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
          child: Row(
            children: [
              const Icon(
                Icons.calendar_today_rounded,
                color: AppColors.primaryYellow,
                size: 16,
              ),
              const SizedBox(width: 8),
              const Text(
                'انتخاب روز',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '${days.length} روز',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: days.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final day = days[index] as Map;
              final dateStr = day['date'].toString();
              final dt = DateTime.parse(dateStr);
              final isSelected = index == _selectedDayIndex;
              final isToday = _isToday(dt);
              final jalali = _toJalaliParts(dt);

              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedDayIndex = index);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  width: 68,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFFFD54F), Color(0xFFFFC107)],
                          )
                        : null,
                    color: isSelected ? null : AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primaryYellow
                          : Colors.white.withValues(alpha: 0.08),
                      width: isSelected ? 2 : 1,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppColors.primaryYellow
                                  .withValues(alpha: 0.3),
                              blurRadius: 14,
                              offset: const Offset(0, 5),
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _persianWeekDay(dt),
                        style: TextStyle(
                          color: isSelected ? Colors.black87 : Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${jalali.day}',
                        style: TextStyle(
                          color: isSelected ? Colors.black : Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _monthName(jalali.month),
                        style: TextStyle(
                          color: isSelected
                              ? Colors.black54
                              : AppColors.textSecondary,
                          fontSize: 9,
                        ),
                      ),
                      if (isToday) ...[
                        const SizedBox(height: 4),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.black54
                                : AppColors.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ============================================================
  // SLOTS LIST
  // ============================================================

  Widget _buildSlotsList(List days) {
    if (days.isEmpty) return const SizedBox.shrink();
    if (_selectedDayIndex >= days.length) _selectedDayIndex = 0;

    final selectedDay = days[_selectedDayIndex] as Map;
    final slots = selectedDay['slots'] as List? ?? [];
    final dayDateStr = selectedDay['date']?.toString() ?? '';

    if (slots.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.event_busy_rounded,
                color: AppColors.textSecondary,
                size: 44,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'شیفتی برای این روز تعریف نشده',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
          child: Row(
            children: [
              const Icon(
                Icons.access_time_rounded,
                color: AppColors.primaryYellow,
                size: 16,
              ),
              const SizedBox(width: 8),
              const Text(
                'شیفت‌های موجود',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryYellow.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${slots.length} شیفت',
                  style: const TextStyle(
                    color: AppColors.primaryYellow,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: slots
                .map<Widget>((s) => _buildSlotCard(
                      s as Map<String, dynamic>,
                      dayDateStr,
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // SLOT CARD
  // ============================================================

  Widget _buildSlotCard(Map<String, dynamic> slot, String dayDateStr) {
    final label = slot['label']?.toString() ?? '';
    final capacity = (slot['capacity'] as num?)?.toInt() ?? 0;
    final assigned = (slot['assignedCount'] as num?)?.toInt() ?? 0;
    final remaining = (slot['remaining'] as num?)?.toInt() ?? 0;
    final isPaid = slot['isPaid'] == true;
    final price = (slot['price'] as num?)?.toDouble() ?? 0;
    final guarantee = (slot['guaranteeAmount'] as num?)?.toDouble() ?? 0;
    final canTake = slot['canTake'] == true;
    final alreadyTaken = slot['alreadyTaken'] == true;
    final reason = slot['reason']?.toString();
    final assignmentId = slot['assignmentId']?.toString();
    final shiftSlot = slot['shiftSlot']?.toString() ?? '';

    final progress = capacity > 0 ? assigned / capacity : 0.0;
    final isFull = remaining <= 0;

    Color accentColor;
    if (alreadyTaken) {
      accentColor = AppColors.success;
    } else if (isFull) {
      accentColor = AppColors.danger;
    } else if (isPaid) {
      accentColor = AppColors.primaryYellow;
    } else {
      accentColor = AppColors.success;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accentColor.withValues(alpha: alreadyTaken ? 0.4 : 0.15),
          width: alreadyTaken ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          if (alreadyTaken)
            BoxShadow(
              color: AppColors.success.withValues(alpha: 0.08),
              blurRadius: 20,
              spreadRadius: 1,
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              height: 3,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accentColor.withValues(alpha: 0.2),
                    accentColor,
                    accentColor.withValues(alpha: 0.2),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSlotHeader(
                    label: label,
                    isPaid: isPaid,
                    price: price,
                    accentColor: accentColor,
                  ),
                  const SizedBox(height: 12),
                  if (guarantee > 0) ...[
                    _buildGuaranteeBadge(guarantee),
                    const SizedBox(height: 12),
                  ],
                  _buildCapacityBar(
                    assigned: assigned,
                    capacity: capacity,
                    remaining: remaining,
                    accentColor: accentColor,
                  ),
                  const SizedBox(height: 14),
                  _buildActionRow(
                    slot: slot,
                    canTake: canTake,
                    alreadyTaken: alreadyTaken,
                    assignmentId: assignmentId,
                    reason: reason,
                    isPaid: isPaid,
                    price: price,
                    accentColor: accentColor,
                    shiftDate: dayDateStr,
                    shiftSlot: shiftSlot,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlotHeader({
    required String label,
    required bool isPaid,
    required double price,
    required Color accentColor,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(
            Icons.access_time_rounded,
            color: accentColor,
            size: 18,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                isPaid ? 'شیفت پولی' : 'شیفت رایگان',
                style: TextStyle(
                  color: isPaid ? AppColors.primaryYellow : AppColors.success,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isPaid
                ? AppColors.primaryYellow.withValues(alpha: 0.12)
                : AppColors.success.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isPaid
                  ? AppColors.primaryYellow.withValues(alpha: 0.3)
                  : AppColors.success.withValues(alpha: 0.3),
            ),
          ),
          child: Text(
            isPaid ? '${DriverService.formatToman(price)} ت' : 'رایگان',
            style: TextStyle(
              color: isPaid ? AppColors.primaryYellow : AppColors.success,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGuaranteeBadge(double guarantee) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.success.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded,
              color: AppColors.success, size: 16),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'گارانتی تشویقی',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
          Text(
            '${DriverService.formatToman(guarantee)} تومان',
            style: const TextStyle(
              color: AppColors.success,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapacityBar({
    required int assigned,
    required int capacity,
    required int remaining,
    required Color accentColor,
  }) {
    final progress = capacity > 0 ? assigned / capacity : 0.0;
    final isFull = remaining <= 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.people_alt_outlined,
              color: AppColors.textSecondary,
              size: 14,
            ),
            const SizedBox(width: 6),
            const Text(
              'ظرفیت',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isFull
                    ? AppColors.danger.withValues(alpha: 0.12)
                    : AppColors.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isFull ? 'تکمیل' : '$remaining جای خالی',
                style: TextStyle(
                  color: isFull ? AppColors.danger : AppColors.success,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$assigned / $capacity',
              style: TextStyle(
                color: isFull ? AppColors.danger : AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) {
              return LinearProgressIndicator(
                value: value,
                minHeight: 7,
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                valueColor: AlwaysStoppedAnimation(
                  isFull ? AppColors.danger : accentColor,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildActionRow({
    required Map<String, dynamic> slot,
    required bool canTake,
    required bool alreadyTaken,
    required String? assignmentId,
    required String? reason,
    required bool isPaid,
    required double price,
    required Color accentColor,
    required String shiftDate,
    required String shiftSlot,
  }) {
    if (alreadyTaken && assignmentId != null) {
      return Row(
        children: [
          Expanded(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle,
                      color: AppColors.success, size: 16),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'این شیفت را گرفته‌اید',
                      style: TextStyle(
                        color: AppColors.success,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _cancelShift(
                assignmentId: assignmentId,
                shiftDate: shiftDate,
                shiftSlot: shiftSlot,
              ),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.danger.withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cancel_outlined,
                        color: AppColors.danger, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'لغو',
                      style: TextStyle(
                        color: AppColors.danger,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (canTake) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _takeShift(slot),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isPaid
                    ? const [Color(0xFFFFD54F), Color(0xFFFFC107)]
                    : const [Color(0xFF4CAF50), Color(0xFF2E7D32)],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isPaid
                      ? Icons.shopping_cart_checkout_rounded
                      : Icons.touch_app_rounded,
                  color: Colors.black,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  isPaid
                      ? 'خرید شیفت — ${DriverService.formatToman(price)} تومان'
                      : 'گرفتن شیفت رایگان',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.block_rounded,
              color: AppColors.textSecondary, size: 16),
          const SizedBox(width: 8),
          Text(
            reason ?? 'غیرقابل انتخاب',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}