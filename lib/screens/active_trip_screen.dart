import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audioplayers/audioplayers.dart';

import '../services/driver_service.dart';
import '../theme/app_theme.dart';

// تعریف مراحل سفر شامل مراحل مرجوعی
enum TripStage { 
  accepted, 
  arrivedPickup, 
  pickedUp, 
  arrivedDest, 
  delivered, 
  returnToOrigin,       // سفارش مرجوع شد، منتظر حرکت
  arrivedOrigin,        // به مبدا اولیه رسید
  handedToSender        // تحویل به فرستنده (پایان)
}

class ActiveTripScreen extends StatefulWidget {
  final String driverId;
  final String orderId;
  final Map<String, dynamic> orderData;

  const ActiveTripScreen({
    super.key,
    required this.driverId,
    required this.orderId,
    required this.orderData,
  });

  @override
  State<ActiveTripScreen> createState() => _ActiveTripScreenState();
}

class _ActiveTripScreenState extends State<ActiveTripScreen> {
  static const LatLng _defaultPosition = LatLng(37.2808, 49.5832);

  final MapController _mapController = MapController();
  final AudioPlayer _audioPlayer = AudioPlayer();

  TripStage _stage = TripStage.accepted;
  bool _loading = false;
  bool _isHolding = false;
  bool _cancellationHandled = false;
  bool _audioPreloaded = false;
  bool _hasIssueReport = false;
  Map<String, dynamic>? _issueReport;

  Timer? _holdTimer;
  Timer? _refreshTimer;
  StreamSubscription<Position>? _positionStream;

  late LatLng _origin;
  late LatLng _driverPos;

  final List<Map<String, dynamic>> _destData = [];
  final List<LatLng> _destinations = [];

  String _originAddress = 'مبدأ نامشخص';
  String _customerMobile = '';

  int _currentDestinationIndex = 0;
  late Map<String, dynamic> _orderData;

  LatLng? _readPoint(dynamic lat, dynamic lng) {
    final latitude = double.tryParse(lat?.toString() ?? '');
    final longitude = double.tryParse(lng?.toString() ?? '');

    if (latitude == null ||
        longitude == null ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180 ||
        (latitude == 0 && longitude == 0)) {
      return null;
    }
    return LatLng(latitude, longitude);
  }

  List<Map<String, dynamic>> get _orderItems {
    final result = <Map<String, dynamic>>[];
    final orderItems = _orderData['items'];
    if (orderItems is List && orderItems.isNotEmpty) {
      for (final raw in orderItems) {
        if (raw is Map) result.add(Map<String, dynamic>.from(raw));
      }
      if (result.isNotEmpty) return result;
    }
    for (final destination in _destData) {
      final rawItems = destination['items'];
      if (rawItems is! List) continue;
      for (final raw in rawItems) {
        if (raw is Map) {
          result.add({
            ...Map<String, dynamic>.from(raw),
            '_destinationAddress': destination['address']?.toString() ?? '',
          });
        }
      }
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    _orderData = Map<String, dynamic>.from(widget.orderData);
    _applyOrderData(_orderData);
    _initLocationStream();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _audioPlayer.setSource(AssetSource('sounds/offer_alert.mp3'));
      } catch (e) {
        debugPrint('PRELOAD AUDIO ERROR: $e');
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _fitMap());

    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final fresh = await DriverService.getSingleTrip(
        driverId: widget.driverId,
        orderId: widget.orderId,
      );
      if (fresh != null && mounted) {
        setState(() {
          _orderData = fresh;
          _applyOrderData(fresh, preserveDriverPos: true);
        });
      } else if (fresh == null && mounted && !_cancellationHandled) {
        _handleCancellation('CANCELLED_BY_SYSTEM');
      }
    });
  }

  void _applyOrderData(Map<String, dynamic> data, {bool preserveDriverPos = false}) {
    final dataOrigin = _readPoint(data['originLat'], data['originLng']) ?? _defaultPosition;
    _origin = dataOrigin;
    if (!preserveDriverPos) _driverPos = _origin;
    _originAddress = data['originAddress']?.toString() ?? 'مبدأ نامشخص';
    _customerMobile = data['customerMobile']?.toString() ?? '';

    _destData.clear();
    _destinations.clear();

    final rawDestinations = data['destinations'];
    if (rawDestinations is List && rawDestinations.isNotEmpty) {
      for (final raw in rawDestinations) {
        if (raw is! Map) continue;
        final destination = Map<String, dynamic>.from(raw);
        final point = _readPoint(destination['lat'], destination['lng']);
        if (point == null) continue;
        _destData.add(destination);
        _destinations.add(point);
      }
    }

    if (_destinations.isEmpty) {
      final point = _readPoint(data['destLat'], data['destLng']);
      if (point != null) {
        _destinations.add(point);
        _destData.add({
          'id': data['destId'],
          'lat': point.latitude,
          'lng': point.longitude,
          'address': data['destAddress'] ?? 'مقصد',
          'receiverMobile': data['receiverMobile'] ?? '',
          'items': data['items'] ?? [],
        });
      }
    }

    final status = data['status']?.toString() ?? '';

    // بررسی سفارش‌های لغو شده
    final cancelledStatuses = [
      'CANCELLED_BY_DRIVER',
      'CANCELLED_BY_CUSTOMER',
      'CANCELLED_BY_SYSTEM',
      'PENDING_DRIVER',
    ];

    if (cancelledStatuses.contains(status) && _stage != TripStage.delivered) {
      String msg = 'این سفارش لغو شد. لطفاً به خانه بازگردید.';
      if (status == 'PENDING_DRIVER') {
        msg = 'این سفارش از شما برداشته شد و به صف تخصیص بازگشت.';
      }
      _handleCancellation(status, customMessage: msg);
      return;
    }

    // مدیریت وضعیت‌های مرجوعی
    if (status == 'RETURNED_TO_ORIGIN') {
      _stage = TripStage.returnToOrigin;
      return;
    } else if (status == 'RETURN_ARRIVED_ORIGIN') {
      _stage = TripStage.arrivedOrigin;
      return;
    } else if (status == 'RETURN_COMPLETED') {
      _stage = TripStage.handedToSender;
      return;
    }

    // مدیریت سفارش‌های دارای مشکل
    if (status == 'PENDING_ISSUE_REVIEW') {
      _hasIssueReport = true;
      _issueReport = data['issueReport'];
      return;
    } else {
      _hasIssueReport = false;
      _issueReport = null;
    }

    // مدیریت مراحل عادی سفر
    switch (status) {
      case 'DRIVER_ASSIGNED':
        _stage = TripStage.accepted;
        break;
      case 'DRIVER_ARRIVED_PICKUP':
        _stage = TripStage.arrivedPickup;
        break;
      case 'PICKED_UP':
        _stage = TripStage.pickedUp;
        break;
      case 'DELIVERED':
        _stage = TripStage.delivered;
        break;
    }

    int currentIdx = -1;
    for (int i = 0; i < _destData.length; i++) {
      final deliveredAt = _destData[i]['deliveredAt'];
      if (deliveredAt == null || deliveredAt.toString().isEmpty) {
        currentIdx = i;
        break;
      }
    }
    if (currentIdx == -1) {
      _currentDestinationIndex = _destData.isNotEmpty ? _destData.length - 1 : 0;
    } else {
      _currentDestinationIndex = currentIdx;
    }

    if (_stage == TripStage.pickedUp && currentIdx != -1) {
      final dest = _destData[currentIdx];
      final arrivedAt = dest['arrivedAt'];
      if (arrivedAt != null && arrivedAt.toString().isNotEmpty) {
        _stage = TripStage.arrivedDest;
      }
    }
  }

  void _handleCancellation(String status, {String? customMessage}) async {
    if (_cancellationHandled) return;
    _cancellationHandled = true;

    HapticFeedback.heavyImpact();

    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('sounds/offer_alert.mp3'));
    } catch (e) {
      debugPrint('CANCELLATION AUDIO ERROR: $e');
      try {
        SystemSound.play(SystemSoundType.alert);
      } catch (_) {}
    }

    if (!mounted) return;

    final message = customMessage ?? 'این سفارش لغو شد. لطفاً به خانه بازگردید.';

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF17191D),
          icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 54),
          title: const Text('تغییر وضعیت سفارش', style: TextStyle(color: Colors.white)),
          content: Text(
            message,
            style: const TextStyle(color: Colors.white70, height: 1.6),
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.pop(context, true);
              },
              child: const Text('بازگشت به خانه', style: TextStyle(color: AppColors.primaryYellow)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _initLocationStream() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _driverPos = LatLng(position.latitude, position.longitude);
        });
      }
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((position) {
        if (!mounted) return;
        setState(() {
          _driverPos = LatLng(position.latitude, position.longitude);
        });
      });
    } catch (e) {
      debugPrint('TRIP LOCATION ERROR: $e');
    }
  }

  void _fitMap() {
    if (!mounted) return;
    final points = <LatLng>[_driverPos, _origin, ..._destinations];
    if (points.length < 2) return;
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(55),
        ),
      );
    } catch (e) {
      debugPrint('TRIP MAP FIT ERROR: $e');
    }
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _refreshTimer?.cancel();
    _positionStream?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  String get _stageLabel {
    switch (_stage) {
      case TripStage.accepted: return 'به مبدأ رسیدم';
      case TripStage.arrivedPickup: return 'سفارش را تحویل گرفتم';
      case TripStage.pickedUp: return 'به مقصد ${_currentDestinationIndex + 1} رسیدم';
      case TripStage.arrivedDest: return 'سفارش را تحویل دادم';
      case TripStage.delivered: return 'پایان سفر';
      case TripStage.returnToOrigin: return 'بازگشت به مبدا';
      case TripStage.arrivedOrigin: return 'به مبدا اولیه رسیدم';
      case TripStage.handedToSender: return 'بسته را به فرستنده تحویل دادم';
    }
  }

  IconData get _stageIcon {
    switch (_stage) {
      case TripStage.accepted: return Icons.navigation;
      case TripStage.arrivedPickup: return Icons.inventory_2_outlined;
      case TripStage.pickedUp: return Icons.location_on_outlined;
      case TripStage.arrivedDest: return Icons.task_alt;
      case TripStage.delivered: return Icons.done_all;
      case TripStage.returnToOrigin: return Icons.keyboard_return;
      case TripStage.arrivedOrigin: return Icons.home_filled;
      case TripStage.handedToSender: return Icons.person_pin_circle;
    }
  }

  String get _stageDescription {
    if (_hasIssueReport) {
      return 'شما برای این سفارش مشکل گزارش کرده‌اید. تا بررسی پشتیبانی، امکان تغییر مرحله وجود ندارد.';
    }
    switch (_stage) {
      case TripStage.accepted: return 'پس از رسیدن به محل دریافت سفارش، دکمه را نگه دارید.';
      case TripStage.arrivedPickup: return 'اقلام سفارش را بررسی کنید و پس از تحویل گرفتن بسته، دکمه را نگه دارید.';
      case TripStage.pickedUp: return 'پس از رسیدن به مقصد مشخص‌شده، دکمه را نگه دارید.';
      case TripStage.arrivedDest: return 'پس از تحویل سفارش به گیرنده، مرحله پایانی را تأیید کنید.';
      case TripStage.delivered: return 'این سفر به پایان رسیده است.';
      case TripStage.returnToOrigin: return 'پشتیبانی این سفارش را مرجوع کرده است. لطفاً به مبدا اولیه بازگردید.';
      case TripStage.arrivedOrigin: return 'شما به مبدا رسیده‌اید. لطفاً بسته را به فرستنده تحویل دهید.';
      case TripStage.handedToSender: return 'بسته با موفقیت به فرستنده تحویل داده شد.';
    }
  }

  String? get _currentDestinationId {
    if (_currentDestinationIndex >= _destData.length) return null;
    final id = _destData[_currentDestinationIndex]['id'];
    if (id == null || id.toString().isEmpty) return null;
    return id.toString();
  }

  void _preloadAudioOnce() async {
    if (_audioPreloaded) return;
    _audioPreloaded = true;
    try {
      await _audioPlayer.setSource(AssetSource('sounds/offer_alert.mp3'));
    } catch (e) {
      debugPrint('AUDIO PRELOAD ERROR: $e');
    }
  }

  void _startHold() {
    if (_loading) return;
    if (_stage == TripStage.returnToOrigin || _stage == TripStage.arrivedOrigin || _stage == TripStage.handedToSender) return;
    if (_stage == TripStage.delivered) return;
    
    if (_hasIssueReport) {
      _showMessage('این سفارش در انتظار بررسی پشتیبانی است.', isError: true);
      return;
    }
    if (_isHolding) return;

    _preloadAudioOnce();
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);

    setState(() => _isHolding = true);
    _holdTimer?.cancel();
    _holdTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted || !_isHolding) return;
      setState(() => _isHolding = false);
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
      _advanceStage();
    });
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    if (!mounted || !_isHolding) return;
    setState(() => _isHolding = false);
  }

  // 👈 تابع ارسال مراحل مرجوعی به سرور
  Future<void> _handleReturnAction(String action) async {
    setState(() => _loading = true);
    try {
      final result = await DriverService.updateOrderStatus(
        orderId: widget.orderId,
        driverId: widget.driverId,
        action: action, 
        destId: null,
        lat: _driverPos.latitude,
        lng: _driverPos.longitude,
      );

      if (!mounted) return;
      setState(() => _loading = false);

      if (result['success'] != true) {
        _showMessage(result['message']?.toString() ?? 'خطا در تغییر وضعیت', isError: true);
        return;
      }

      final fresh = await DriverService.getSingleTrip(
        driverId: widget.driverId,
        orderId: widget.orderId,
      );
      if (fresh != null && mounted) {
        setState(() {
          _orderData = fresh;
          _applyOrderData(fresh, preserveDriverPos: true);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('خطا: $e', isError: true);
    }
  }

  Future<void> _advanceStage() async {
    if (_loading || _stage == TripStage.delivered || _hasIssueReport) return;
    if (_stage == TripStage.returnToOrigin || _stage == TripStage.arrivedOrigin || _stage == TripStage.handedToSender) return;
    
    setState(() => _loading = true);

    String action;
    switch (_stage) {
      case TripStage.accepted: action = 'ARRIVED_PICKUP'; break;
      case TripStage.arrivedPickup: action = 'PICKED_UP'; break;
      case TripStage.pickedUp: action = 'ARRIVED_DEST'; break;
      case TripStage.arrivedDest: action = 'DELIVERED'; break;
      default: setState(() => _loading = false); return;
    }

    if (action == 'ARRIVED_PICKUP' || action == 'ARRIVED_DEST') {
      final targetPoint = action == 'ARRIVED_PICKUP' ? _origin : (_currentDestinationIndex < _destinations.length ? _destinations[_currentDestinationIndex] : null);
      if (targetPoint != null) {
        final rules = await DriverService.getPolygonRules(lat: targetPoint.latitude, lng: targetPoint.longitude);
        if (rules != null) {
          final enabled = action == 'ARRIVED_PICKUP' ? rules['pickupArrivalRadiusEnabled'] == true : rules['deliveryArrivalRadiusEnabled'] == true;
          final radius = action == 'ARRIVED_PICKUP' ? (rules['pickupArrivalRadiusM'] as num?)?.toDouble() ?? 0 : (rules['deliveryArrivalRadiusM'] as num?)?.toDouble() ?? 0;
          if (enabled && radius > 0) {
            final distanceM = const Distance().as(LengthUnit.Meter, _driverPos, targetPoint);
            if (distanceM > radius) {
              if (!mounted) return;
              setState(() => _loading = false);
              _showMessage('شما هنوز به ${action == 'ARRIVED_PICKUP' ? 'مبدا' : 'مقصد'} نرسیده‌اید. فاصله فعلی: ${distanceM.round()} متر، مجاز: ${radius.round()} متر', isError: true);
              return;
            }
          }
        }
      }
    }

    try {
      final result = await DriverService.updateOrderStatus(
        orderId: widget.orderId,
        driverId: widget.driverId,
        action: action,
        destId: action == 'ARRIVED_DEST' || action == 'DELIVERED' ? _currentDestinationId : null,
        lat: _driverPos.latitude,
        lng: _driverPos.longitude,
      );

      if (!mounted) return;
      setState(() => _loading = false);

      if (result['success'] != true) {
        _showMessage(result['message']?.toString() ?? 'به‌روزرسانی وضعیت ناموفق بود', isError: true);
        return;
      }

      final fresh = await DriverService.getSingleTrip(driverId: widget.driverId, orderId: widget.orderId);
      if (fresh != null && mounted) {
        setState(() {
          _orderData = fresh;
          _applyOrderData(fresh, preserveDriverPos: true);
        });
      }
      if (_stage == TripStage.delivered) _showSuccessDialog();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('خطا در ارتباط با سرور: $e', isError: true);
    }
  }

  Future<void> _cancelTrip() async {
    if (_loading) return;
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF17191D),
          title: const Text('لغو سفر', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('آیا از لغو این سفارش مطمئن هستید؟', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'دلیل لغو (اختیاری)',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF24272D),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('انصراف'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('تأیید لغو', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (reason == null || !mounted) return;
    setState(() => _loading = true);

    try {
      final result = await DriverService.cancelOrderByDriver(
        orderId: widget.orderId,
        driverId: widget.driverId,
        reason: reason,
      );
      if (!mounted) return;
      setState(() => _loading = false);

      if (result['success'] == true) {
        HapticFeedback.heavyImpact();
        _showMessage('سفارش لغو شد و به صف تخصیص بازگشت.');
        Navigator.pop(context, true);
      } else {
        _showMessage(result['message']?.toString() ?? 'لغو ناموفق بود', isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('خطا در لغو: $e', isError: true);
    }
  }

  Future<void> _reportIssue() async {
    final destId = _currentDestinationId;
    if (destId == null) {
      _showMessage('مقصد جاری مشخص نیست', isError: true);
      return;
    }

    final reason = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF17191D),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      isScrollControlled: true,
      builder: (sheetContext) {
        return _IssueReasonSheet(onSelect: (value) => Navigator.pop(sheetContext, value));
      },
    );

    if (reason == null || !mounted) return;

    String? note;
    if (reason == 'OTHER') {
      final noteController = TextEditingController();
      final typed = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: const Color(0xFF17191D),
            title: const Text('توضیح مشکل', style: TextStyle(color: Colors.white)),
            content: TextField(
              controller: noteController,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'مشکل را شرح دهید...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF24272D),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('انصراف'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, noteController.text.trim()),
                child: const Text('ثبت', style: TextStyle(color: Colors.red)),
              ),
            ],
          );
        },
      );
      noteController.dispose();
      if (typed == null || typed.isEmpty || !mounted) return;
      note = typed;
    }

    setState(() => _loading = true);
    try {
      final result = await DriverService.reportOrderIssue(
        orderId: widget.orderId,
        driverId: widget.driverId,
        destId: destId,
        reason: reason,
        note: note,
      );
      if (!mounted) return;
      setState(() => _loading = false);

      if (result['success'] == true) {
        HapticFeedback.heavyImpact();
        _showMessage(result['message']?.toString() ?? 'گزارش ثبت شد. منتظر بررسی پشتیبانی باشید.');
      } else {
        _showMessage(result['message']?.toString() ?? 'ثبت ناموفق بود', isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('خطا: $e', isError: true);
    }
  }

  Widget _buildPaymentInfoRow() {
    final method = _orderData['paymentMethod']?.toString().toUpperCase() ?? '';
    final status = _orderData['paymentStatus']?.toString().toUpperCase() ?? '';
    final totalPrice = double.tryParse(_orderData['totalPrice']?.toString() ?? '') ?? 0;

    final isCash = method == 'CASH';
    final isPaid = status == 'PAID';

    String text;
    Color color;
    IconData icon;

    if (isCash) {
      text = 'از مشتری مبلغ ${DriverService.formatToman(totalPrice)} تومان به صورت نقدی دریافت کنید.';
      color = Colors.orange;
      icon = Icons.payments_outlined;
    } else if (isPaid) {
      text = 'وجه نقد دریافت نکنید. مبلغ ${DriverService.formatToman(totalPrice)} تومان به حساب شما اضافه می‌شود.';
      color = Colors.green;
      icon = Icons.check_circle_outline;
    } else {
      text = 'وضعیت پرداخت: ${status.isEmpty ? "نامشخص" : status}';
      color = Colors.white70;
      icon = Icons.help_outline;
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 12, height: 1.5)),
          ),
          SizedBox(
            width: 34,
            height: 34,
            child: IconButton(
              onPressed: _reloadOrderData,
              icon: const Icon(Icons.refresh, color: AppColors.primaryYellow, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'بروزرسانی',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _reloadOrderData() async {
    try {
      final fresh = await DriverService.getSingleTrip(
        driverId: widget.driverId,
        orderId: widget.orderId,
      );
      if (fresh != null && mounted) {
        setState(() {
          _orderData = fresh;
          _applyOrderData(fresh, preserveDriverPos: true);
        });
        _showMessage('اطلاعات بروزرسانی شد');
      } else if (mounted) {
        _showMessage('اطلاعات دریافت نشد', isError: true);
      }
    } catch (e) {
      if (mounted) _showMessage('خطا: $e', isError: true);
    }
  }

  void _showItemsModal() {
    final items = _orderItems;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF17191D),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(10)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                    child: Row(
                      children: [
                        const Icon(Icons.inventory_2_outlined, color: AppColors.primaryYellow, size: 24),
                        const SizedBox(width: 9),
                        const Expanded(
                          child: Text('اقلام سفارش', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                        ),
                        Text('${items.length} قلم', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white12, height: 1),
                  Expanded(
                    child: items.isEmpty
                        ? const Center(child: Text('اقلامی ثبت نشده است.', style: TextStyle(color: Colors.white70)))
                        : ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.all(14),
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final item = items[index];
                              final name = item['name'] ?? item['title'] ?? item['productName'] ?? item['itemName'] ?? 'کالای ${index + 1}';
                              final quantity = item['quantity'] ?? item['qty'] ?? item['count'] ?? 1;
                              final destinationAddress = item['_destinationAddress']?.toString() ?? '';

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF24272D),
                                  borderRadius: BorderRadius.circular(11),
                                  border: Border.all(color: Colors.white10),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.inventory_2_outlined, color: AppColors.primaryYellow, size: 19),
                                        const SizedBox(width: 9),
                                        Expanded(
                                          child: Text(name.toString(), overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                        ),
                                        const SizedBox(width: 6),
                                        Text('تعداد: $quantity', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                      ],
                                    ),
                                    if (destinationAddress.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text('مقصد: $destinationAddress', overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildItemsButton() {
    final count = _orderItems.length;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      child: ElevatedButton.icon(
        onPressed: _showItemsModal,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF24272D),
          foregroundColor: AppColors.primaryYellow,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: AppColors.primaryYellow.withValues(alpha: 0.35)),
          ),
        ),
        icon: const Icon(Icons.inventory_2_outlined, size: 20),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Flexible(
              child: Text('مشاهده اقلام سفارش', overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primaryYellow.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('$count', style: const TextStyle(color: AppColors.primaryYellow, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openNavigation(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        _showMessage('باز کردن نقشه ممکن نشد', isError: true);
      }
    } catch (e) {
      if (mounted) _showMessage('برنامه نقشه در دسترس نیست', isError: true);
    }
  }

  Future<void> _makePhoneCall(String phone) async {
    if (phone.trim().isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      await launchUrl(uri);
    } catch (e) {
      if (mounted) _showMessage('برقراری تماس ممکن نشد', isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.danger : AppColors.success,
      ),
    );
  }

  void _showSuccessDialog() {
    if (!mounted) return;
    if (_stage != TripStage.delivered) {
      setState(() => _stage = TripStage.delivered);
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF17191D),
          icon: const Icon(Icons.check_circle, color: AppColors.success, size: 54),
          title: const Text('سفر با موفقیت انجام شد', style: TextStyle(color: Colors.white)),
          content: const Text('سفارش تحویل داده شد. ممنون از همراهی شما.', style: TextStyle(color: Colors.white70), textAlign: TextAlign.center),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.pop(context, true);
              },
              child: const Text('بازگشت به خانه'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLocationCard({
    required IconData icon,
    required Color color,
    required String title,
    required String address,
    String phone = '',
    required VoidCallback onNavigate,
    bool selected = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: selected ? AppColors.primaryYellow.withValues(alpha: 0.08) : const Color(0xFF22252B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: selected ? AppColors.primaryYellow.withValues(alpha: 0.7) : Colors.white10),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 5),
                Text(address.isEmpty ? 'آدرس ثبت نشده' : address, style: const TextStyle(color: Colors.white, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (phone.isNotEmpty) ...[
            const SizedBox(width: 4),
            SizedBox(
              width: 34,
              height: 34,
              child: IconButton(
                onPressed: () => _makePhoneCall(phone),
                icon: const Icon(Icons.phone, color: Colors.white, size: 17),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                style: IconButton.styleFrom(backgroundColor: Colors.white12),
              ),
            ),
          ],
          const SizedBox(width: 4),
          SizedBox(
            width: 34,
            height: 34,
            child: IconButton(
              onPressed: onNavigate,
              icon: const Icon(Icons.directions, color: AppColors.primaryYellow, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              style: IconButton.styleFrom(backgroundColor: AppColors.primaryYellow.withValues(alpha: 0.12)),
            ),
          ),
        ],
      ),
    );
  }

  void _showAllAddresses() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF17191D),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('مبدا و مقصدها', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 14),
                  _buildLocationCard(
                    icon: Icons.trip_origin,
                    color: Colors.green,
                    title: 'مبدأ دریافت سفارش',
                    address: _originAddress,
                    phone: _customerMobile,
                    onNavigate: () {
                      Navigator.pop(sheetContext);
                      _openNavigation(_origin.latitude, _origin.longitude);
                    },
                  ),
                  ..._destData.asMap().entries.map((entry) {
                    final index = entry.key;
                    final destination = entry.value;
                    final point = _destinations[index];
                    return _buildLocationCard(
                      icon: Icons.location_on,
                      color: Colors.orange,
                      title: 'مقصد ${index + 1}',
                      address: destination['address']?.toString() ?? '',
                      phone: destination['receiverMobile']?.toString() ?? '',
                      onNavigate: () {
                        Navigator.pop(sheetContext);
                        _openNavigation(point.latitude, point.longitude);
                      },
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Marker _mapSmallMarker({
    required LatLng point,
    required String label,
    required Color color,
    required IconData icon,
    bool selected = false,
  }) {
    return Marker(
      point: point,
      width: selected ? 92 : 78,
      height: 34,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0F13),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color, width: selected ? 2 : 1.4),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: selected ? 12 : 6),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];
    markers.add(
      _mapSmallMarker(
        point: _origin,
        label: 'مبدا',
        color: Colors.green,
        icon: Icons.trip_origin,
      ),
    );
    for (int i = 0; i < _destinations.length; i++) {
      final isCurrent = i == _currentDestinationIndex;
      markers.add(
        _mapSmallMarker(
          point: _destinations[i],
          label: 'مقصد ${i + 1}',
          color: isCurrent ? Colors.red : Colors.orange,
          icon: Icons.location_on,
          selected: isCurrent,
        ),
      );
    }
    markers.add(
      Marker(
        point: _driverPos,
        width: 48,
        height: 48,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.blue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8)],
          ),
          child: const Icon(Icons.navigation, color: Colors.white),
        ),
      ),
    );
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final canCancel = _stage == TripStage.accepted || _stage == TripStage.arrivedPickup;
    final showItems = _stage == TripStage.arrivedPickup || _stage == TripStage.pickedUp || _stage == TripStage.arrivedDest;
    final showIssueButton = (_stage == TripStage.pickedUp || _stage == TripStage.arrivedDest) && !_hasIssueReport;
    final totalPrice = _orderData['totalPrice'];

    // بررسی اینکه آیا در حالت مرجوعی هستیم یا خیر
    final isReturning = _stage == TripStage.returnToOrigin || _stage == TripStage.arrivedOrigin || _stage == TripStage.handedToSender;

    return Scaffold(
      backgroundColor: const Color(0xFF101216),
      appBar: AppBar(
        backgroundColor: const Color(0xFF17191D),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'سفر #${_orderData['orderCode'] ?? widget.orderId}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _origin,
                initialZoom: 14,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.de/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.rahin.driver',
                ),
                MarkerLayer(markers: _buildMarkers()),
              ],
            ),
          ),
          Positioned(
            top: 14,
            right: 14,
            child: FloatingActionButton.small(
              heroTag: 'trip_my_location',
              backgroundColor: Colors.white,
              onPressed: () => _mapController.move(_driverPos, 16),
              child: const Icon(Icons.my_location, color: Colors.black),
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.48,
            minChildSize: 0.30,
            maxChildSize: 0.88,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF17191D),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
                  boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 18)],
                ),
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Icon(Icons.route, color: AppColors.primaryYellow),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('جزئیات سفر', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                        ),
                        Text('${_destinations.length} مقصد', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                      ],
                    ),
                    if (totalPrice != null) ...[
                      const SizedBox(height: 13),
                      Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: const Color(0xFF24272D),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.payments_outlined, color: AppColors.primaryYellow),
                            const SizedBox(width: 9),
                            const Expanded(child: Text('مبلغ سفارش', style: TextStyle(color: Colors.white70))),
                            Text(
                              '${DriverService.formatToman(totalPrice)} تومان',
                              style: const TextStyle(color: AppColors.primaryYellow, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildPaymentInfoRow(),
                    ],
                    const SizedBox(height: 16),
                    if (_stage == TripStage.accepted || _stage == TripStage.arrivedPickup)
                      _buildLocationCard(
                        icon: Icons.trip_origin,
                        color: Colors.green,
                        title: 'مبدأ دریافت سفارش',
                        address: _originAddress,
                        phone: _customerMobile,
                        onNavigate: () {
                          _openNavigation(_origin.latitude, _origin.longitude);
                        },
                      ),
                    if (_stage == TripStage.pickedUp || _stage == TripStage.arrivedDest)
                      ..._destData.asMap().entries.map((entry) {
                        final index = entry.key;
                        final destination = entry.value;
                        final point = _destinations[index];
                        final phone = destination['receiverMobile']?.toString() ?? '';
                        return _buildLocationCard(
                          icon: Icons.location_on,
                          color: index == _currentDestinationIndex ? Colors.red : Colors.orange,
                          title: 'مقصد ${index + 1}',
                          address: destination['address']?.toString() ?? '',
                          phone: phone,
                          selected: index == _currentDestinationIndex,
                          onNavigate: () {
                            _openNavigation(point.latitude, point.longitude);
                          },
                        );
                      }),
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                      child: TextButton.icon(
                        onPressed: _showAllAddresses,
                        icon: const Icon(Icons.list_alt, color: AppColors.primaryYellow),
                        label: const Text('مشاهده مبدا و مقصدها', style: TextStyle(color: AppColors.primaryYellow)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_hasIssueReport) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.hourglass_top, color: Colors.orange, size: 22),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'شما گزارش مشکل داده‌اید. منتظر بررسی پشتیبانی باشید. دکمه تحویل غیرفعال است.',
                                style: TextStyle(color: Colors.orange, fontSize: 12, height: 1.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF24272D),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(_stageIcon, color: AppColors.primaryYellow, size: 25),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _hasIssueReport ? 'در انتظار بررسی پشتیبانی' : _stageLabel,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(_stageDescription, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                        ],
                      ),
                    ),
                    
                    // 👈 دکمه‌های اختصاصی مرجوعی
                    if (isReturning) ...[
                      const SizedBox(height: 16),
                      if (_stage == TripStage.returnToOrigin)
                        ElevatedButton.icon(
                          onPressed: _loading ? null : () => _handleReturnAction('ARRIVED_ORIGIN'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryYellow,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: const Icon(Icons.home_filled),
                          label: const Text('رسیدم به مبدا اولیه', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        ),
                      if (_stage == TripStage.arrivedOrigin)
                        ElevatedButton.icon(
                          onPressed: _loading ? null : () => _handleReturnAction('HANDED_TO_SENDER'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: const Icon(Icons.person_pin_circle),
                          label: const Text('بسته را به فرستنده تحویل دادم', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        ),
                      if (_stage == TripStage.handedToSender)
                        ElevatedButton.icon(
                          onPressed: _loading ? null : () async {
                            // ارسال اکشن نهایی به سرور برای بستن کامل سفارش
                            setState(() => _loading = true);
                            final result = await DriverService.updateOrderStatus(
                              orderId: widget.orderId,
                              driverId: widget.driverId,
                              action: 'COMPLETE_RETURN', 
                              destId: null,
                              lat: _driverPos.latitude,
                              lng: _driverPos.longitude,
                            );
                            setState(() => _loading = false);

                            if (result['success'] == true) {
                              // اگر سرور تایید کرد، از صفحه خارج شو
                              Navigator.pop(context, true); 
                            } else {
                              _showMessage(result['message'] ?? 'خطا در بستن سفارش', isError: true);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white12,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                            ),
                          ),
                          icon: const Icon(Icons.done_all),
                          label: const Text('پایان و بازگشت به خانه', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        ),
                    ],

                    if (showItems) _buildItemsButton(),
                    const SizedBox(height: 16),
                    
                    // 👈 دکمه اصلی (فقط در حالت عادی)
                    if (!isReturning)
                      GestureDetector(
                        onTapDown: _hasIssueReport ? null : (_) => _startHold(),
                        onTapUp: _hasIssueReport ? null : (_) => _cancelHold(),
                        onTapCancel: _hasIssueReport ? null : _cancelHold,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          height: 60,
                          decoration: BoxDecoration(
                            color: _hasIssueReport
                                ? Colors.grey
                                : _loading
                                    ? Colors.grey
                                    : _isHolding
                                        ? const Color(0xFFD69B00)
                                        : AppColors.primaryYellow,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primaryYellow.withValues(alpha: _isHolding ? 0.35 : 0.15),
                                blurRadius: _isHolding ? 20 : 10,
                              ),
                            ],
                          ),
                          child: Center(
                            child: _loading
                                ? const SizedBox(width: 25, height: 25, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3))
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        _hasIssueReport ? Icons.hourglass_top : _stageIcon,
                                        color: Colors.black,
                                      ),
                                      const SizedBox(width: 10),
                                      Flexible(
                                        child: Text(
                                          _hasIssueReport
                                              ? 'در انتظار بررسی پشتیبانی'
                                              : _isHolding
                                                  ? 'در حال تأیید...'
                                                  : _stageLabel,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    if (showIssueButton) ...[
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: _loading ? null : _reportIssue,
                        child: Container(
                          height: 52,
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.report_problem_outlined, color: Colors.redAccent, size: 20),
                              SizedBox(width: 8),
                              Text('مشکل در سفارش', style: TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 7),
                    if (canCancel)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextButton.icon(
                          onPressed: _loading ? null : _cancelTrip,
                          icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent),
                          label: const Text('لغو سفارش و بازگشت به صف', style: TextStyle(color: Colors.redAccent)),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _IssueReasonSheet extends StatelessWidget {
  final ValueChanged<String> onSelect;

  const _IssueReasonSheet({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final reasons = [
      {'code': 'CUSTOMER_ABSENT', 'title': 'عدم حضور مشتری در آدرس ذکر شده', 'icon': Icons.person_off_outlined},
      {'code': 'RECEIVER_REFUSED', 'title': 'امتناع گیرنده از دریافت', 'icon': Icons.block_outlined},
      {'code': 'CUSTOMER_NOT_RESPONDING', 'title': 'مشتری پاسخگو نیست', 'icon': Icons.phone_disabled_outlined},
      {'code': 'OTHER', 'title': 'سایر (توضیح دستی)', 'icon': Icons.edit_outlined},
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 42, height: 4, decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.report_problem_outlined, color: Colors.redAccent, size: 24),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text('مشکل در سفارش', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text('دلیل مرجوع کردن سفارش را انتخاب کنید:', style: TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 14),
            ...reasons.map((r) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => onSelect(r['code'] as String),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF24272D),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        Icon(r['icon'] as IconData, color: Colors.redAccent, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(r['title'] as String, style: const TextStyle(color: Colors.white, fontSize: 13)),
                        ),
                        const Icon(Icons.arrow_forward_ios, color: Colors.white38, size: 14),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}