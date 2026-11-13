import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';

import '../services/driver_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';

import 'active_trip_screen.dart';
import 'location_picker_modal.dart';
import 'wallet_screen.dart';
import 'orders_history_screen.dart';
import 'shifts_screen.dart';
import 'profile_screen.dart';
import 'messages_screen.dart';

class HomeScreen extends StatefulWidget {
  final String driverId;
  final String? driverName;
  final String? driverAvatarUrl;

  const HomeScreen({
    super.key,
    required this.driverId,
    this.driverName,
    this.driverAvatarUrl,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const LatLng _defaultCenter = LatLng(37.2808, 49.5832);

  final MapController _mapController = MapController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _isOnline = false;
  bool _isFetchingOffers = false;
  bool _isManualLocation = false;
  bool _mapReady = false;
  bool _isOnActiveTripScreen = false;
  bool _offerSheetOpen = false;
  bool _loadingTest = false;
  String _activeNav = 'home';

  Timer? _locationTimer;
  Timer? _offersTimer;
  Timer? _activeTripTimer;
  Timer? _messagesTimer;
  Timer? _blockCheckTimer; // ✅ جدید

  List<dynamic> _offers = [];
  List<Map<String, dynamic>> _activeTrips = [];
  Set<String> _knownTripIds = {};

  // ✅ کلید: (offerId, createdAt) برای تشخیص پیشنهادهای جدید
  final Map<String, DateTime> _seenOffers = {};

  LatLng? _currentPosition;
  String? _avatarUrlFromProfile;

  int _unreadMessagesCount = 0;
  int _lastUnreadCount = 0;
  OverlayEntry? _messageOverlay;
  bool _isDriverBlocked = false;
  String? _blockReason;
  String? _blockType;
  int? _blockRemainingHours;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _initLocation();
    _startTimers();
    _checkActiveTrips();
    _loadDriverProfile();
    _checkBlockStatus(); // ✅ اولین چک فوری

    _activeTripTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _checkActiveTrips(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageOverlay?.remove();
    _locationTimer?.cancel();
    _offersTimer?.cancel();
    _activeTripTimer?.cancel();
    _messagesTimer?.cancel();
    _blockCheckTimer?.cancel(); // ✅ جدید
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _checkBlockStatus(); // ✅ در بازگشت به اپ هم چک کن
      if (_isOnline && _activeTrips.isEmpty) {
        _refreshOffers(silent: true);
      }
      _checkActiveTrips();
    }
  }

  // ============================================================
  // DRIVER PROFILE
  // ============================================================

  Future<void> _loadDriverProfile() async {
    try {
      final result = await DriverService.getProfile(widget.driverId);
      if (!mounted) return;
      if (result['success'] == true) {
        final profile = result['profile'] as Map<String, dynamic>?;
        final photo = profile?['profilePhotoUrl']?.toString();
        if (photo != null && photo.isNotEmpty) {
          setState(() {
            _avatarUrlFromProfile = photo;
          });
        }
      }
    } catch (e) {
      debugPrint('LOAD DRIVER PROFILE ERROR: $e');
    }
  }

  String? _resolveAvatarUrl() {
    final raw = (_avatarUrlFromProfile != null && _avatarUrlFromProfile!.isNotEmpty)
        ? _avatarUrlFromProfile
        : widget.driverAvatarUrl;

    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http')) return raw;
    return '${DriverService.baseUrl.replaceAll('/api/driver-app', '')}$raw';
  }

  void _openOrdersHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrdersHistoryScreen(driverId: widget.driverId),
      ),
    );
  }

  void _openProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(driverId: widget.driverId),
      ),
    ).then((_) {
      _loadDriverProfile();
    });
  }

  void _openMessagesScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MessagesScreen(driverId: widget.driverId),
      ),
    );
    final count = await DriverService.getUnreadMessagesCount(widget.driverId);
    if (mounted) {
      setState(() {
        _unreadMessagesCount = count;
        _lastUnreadCount = count;
      });
    }
  }

  // ============================================================
  // LOCATION
  // ============================================================

  Future<void> _initLocation() async {
    if (_isManualLocation) return;

    try {
      final position = await LocationService.getCurrentPosition();
      if (!mounted) return;

      final point = position == null
          ? _defaultCenter
          : LatLng(position.latitude, position.longitude);

      setState(() {
        _currentPosition = point;
      });

      _moveMapSafely(point, 16);
    } catch (e) {
      debugPrint('INIT LOCATION ERROR: $e');
      if (!mounted) return;
      setState(() {
        _currentPosition = _defaultCenter;
      });
    }
  }

  void _moveMapSafely(LatLng point, double zoom) {
    if (!_mapReady) return;
    try {
      _mapController.move(point, zoom);
    } catch (e) {
      debugPrint('MAP MOVE ERROR: $e');
    }
  }

  Future<void> _sendCurrentLocation() async {
    if (!_isOnline || _activeTrips.isNotEmpty) return;

    if (_isManualLocation) {
      final point = _currentPosition;
      if (point == null) return;
      await DriverService.updateLocation(
        driverId: widget.driverId,
        lat: point.latitude,
        lng: point.longitude,
        isAvailable: true,
      );
      return;
    }

    try {
      final position = await LocationService.getCurrentPosition();
      if (position == null || !mounted) return;
      final point = LatLng(position.latitude, position.longitude);
      setState(() {
        _currentPosition = point;
      });
      await DriverService.updateLocation(
        driverId: widget.driverId,
        lat: point.latitude,
        lng: point.longitude,
        isAvailable: true,
      );
    } catch (e) {
      debugPrint('SEND LOCATION ERROR: $e');
    }
  }

  // ============================================================
  // TIMERS
  // ============================================================

  void _startTimers() {
    _locationTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _sendCurrentLocation(),
    );

    // ✅ تایمر چک مسدودی (هر ۴ ثانیه)
    _blockCheckTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      _checkBlockStatus();
    });

    _offersTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (!mounted) return;
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle != AppLifecycleState.resumed) return;

      // ✅ اگه مسدود هست، پیشنهاد نگیر
      if (_isDriverBlocked) return;

      if (_isOnline && _activeTrips.isEmpty) {
        await _refreshOffers(silent: true);
      }
    });

    _messagesTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      final count = await DriverService.getUnreadMessagesCount(widget.driverId);
      if (!mounted) return;

      if (count > _lastUnreadCount) {
        _showNewMessagePopup();
      }

      _lastUnreadCount = count;
      if (count != _unreadMessagesCount) {
        setState(() => _unreadMessagesCount = count);
      }
    });
  }

  // ============================================================
  // NEW MESSAGE POPUP
  // ============================================================

  void _showNewMessagePopup() {
    if (_messageOverlay != null) return;

    _messageOverlay = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 70,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: () {
              _messageOverlay?.remove();
              _messageOverlay = null;
              _openMessagesScreen();
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF202329),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primaryYellow, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryYellow.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.mail, color: AppColors.primaryYellow, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'پیام جدید دارید!',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'برای مشاهده کلیک کنید',
                          style: TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 14),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_messageOverlay!);

    Timer(const Duration(seconds: 5), () {
      _messageOverlay?.remove();
      _messageOverlay = null;
    });
  }

  // ============================================================
  // ACTIVE TRIPS
  // ============================================================

  Future<void> _checkActiveTrips() async {
    try {
      final trips = await DriverService.getActiveTrips(widget.driverId);
      if (!mounted) return;

      final previousIds = _activeTrips.map((t) => t['id']?.toString() ?? '').toSet();
      final newIds = trips.map((t) => t['id']?.toString() ?? '').toSet();
      final removedIds = previousIds.difference(newIds);

      // ✅ سفرهای جدید = سفرهایی که در _knownTripIds نبودن
      final addedIds = newIds.difference(_knownTripIds);

      // ✅ اگر سفر جدیدی اضافه شده (از بک‌آفیس یا هر جای دیگر)
      if (addedIds.isNotEmpty) {
        final newTrip = trips.firstWhere(
          (t) => addedIds.contains(t['id']?.toString() ?? ''),
          orElse: () => <String, dynamic>{},
        );

        if (newTrip.isNotEmpty) {
          _notifyNewOffer();

          final orderId = newTrip['id']?.toString() ?? '';
          final orderCode = newTrip['orderCode']?.toString() ?? '';
          final originAddress = newTrip['originAddress']?.toString() ?? '';
          final isFromBackoffice = newTrip['assignedByBackoffice'] == true;

          NotificationService.showNewOfferNotification(
            notificationId: orderId.hashCode,
            orderCode: orderCode,
            originAddress: originAddress,
            destAddress: isFromBackoffice
                ? 'سفارش از سمت پشتیبانی تخصیص یافت'
                : 'سفر جدید',
            price: '—',
            orderId: orderId,
          ).catchError((e) {
            debugPrint('NOTIFICATION ERROR: $e');
          });

          if (mounted) {
            _showMessage(
              isFromBackoffice
                  ? 'سفارش جدید از سمت پشتیبانی تخصیص یافت'
                  : 'سفر جدید به شما تخصیص یافت',
            );
          }
        }
      }

      if (removedIds.isNotEmpty && _activeTrips.isNotEmpty) {
        try {
          await _audioPlayer.play(AssetSource('sounds/offer_alert.mp3'));
        } catch (_) {}
        HapticFeedback.heavyImpact();
        HapticFeedback.vibrate();
        if (mounted) {
          _showMessage('یک سفارش از شما برداشته شد و به صف تخصیص بازگشت.', isError: true);
        }
      }

      _knownTripIds = newIds;

      setState(() {
        _activeTrips = trips;
        if (trips.isNotEmpty) {
          _offers = [];
        }
      });
    } catch (e) {
      debugPrint('CHECK ACTIVE TRIPS ERROR: $e');
    }
  }

  // ============================================================
  // CHECK BLOCK STATUS (چک کردن مسدودی هر ۴ ثانیه)
  // ============================================================
  Future<void> _checkBlockStatus() async {
    try {
      final result = await DriverService.checkBlockStatus(widget.driverId);

      if (!mounted) return;

      if (result['success'] == true) {
        final isBlocked = result['isBlocked'] == true;

        if (isBlocked) {
          setState(() {
            _isDriverBlocked = true;
            _blockReason = result['blockReason']?.toString();
            _blockType = result['blockType']?.toString();
            _blockRemainingHours = result['remainingHours'] != null
                ? (result['remainingHours'] as num).toInt()
                : null;

            _isOnline = false;
            _offers = [];
          });

          try {
            _audioPlayer.stop();
          } catch (_) {}
        } else {
          if (_isDriverBlocked) {
            setState(() {
              _isDriverBlocked = false;
              _blockReason = null;
              _blockType = null;
              _blockRemainingHours = null;
            });
            _showMessage('مسدودی حساب شما رفع شد. می‌تونید آنلاین بشید.', isError: false);
          }
        }
      }
    } catch (e) {
      debugPrint('CHECK BLOCK STATUS ERROR: $e');
    }
  }

  Future<void> _openTripScreen({
    required String orderId,
    required Map<String, dynamic> orderData,
  }) async {
    if (!mounted || _isOnActiveTripScreen) return;
    _isOnActiveTripScreen = true;

    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ActiveTripScreen(
            driverId: widget.driverId,
            orderId: orderId,
            orderData: orderData,
          ),
        ),
      );
    } catch (e) {
      debugPrint('OPEN ACTIVE TRIP ERROR: $e');
    } finally {
      _isOnActiveTripScreen = false;
      if (mounted) {
        await _checkActiveTrips();
      }
    }
  }

  void _openActiveTripByIndex(int index) {
    if (index < 0 || index >= _activeTrips.length) return;
    final trip = _activeTrips[index];
    final orderId = (trip['id'] ?? trip['orderId'] ?? trip['order_id'] ?? '').toString();

    if (orderId.isEmpty) {
      _showMessage('شناسه سفارش فعال مشخص نیست', isError: true);
      return;
    }
    _openTripScreen(orderId: orderId, orderData: trip);
  }

  // ============================================================
  // OFFERS
  // ============================================================

  String _offerIdentifier(dynamic offer) {
    if (offer is! Map) return '';
    return (offer['offerId'] ?? offer['id'] ?? '').toString();
  }

  Future<void> _refreshOffers({bool silent = false}) async {
    if (_isFetchingOffers || !_isOnline || _activeTrips.isNotEmpty || _isDriverBlocked) return;

    if (mounted) {
      setState(() => _isFetchingOffers = true);
    }

    try {
      final offers = await DriverService.getOffers(widget.driverId);
      if (!mounted) return;

      final freshOffers = offers.where((offer) {
        if (offer is! Map) return false;
        final id = _offerIdentifier(offer);
        if (id.isEmpty) return false;

        final createdAtStr = offer['createdAt']?.toString() ?? '';
        if (createdAtStr.isEmpty) {
          return !_seenOffers.containsKey(id);
        }

        final createdAt = DateTime.tryParse(createdAtStr) ?? DateTime.now();
        final lastSeen = _seenOffers[id];

        if (lastSeen == null) return true;
        return createdAt.isAfter(lastSeen);
      }).toList();

      setState(() {
        _offers = freshOffers;
        _isFetchingOffers = false;
      });

      if (_offers.isNotEmpty) {
        _fitOffersOnMap();
      }

      if (freshOffers.isNotEmpty) {
        for (final offer in freshOffers) {
          if (offer is! Map) continue;
          final id = _offerIdentifier(offer);
          final createdAtStr = offer['createdAt']?.toString() ?? '';
          final createdAt = DateTime.tryParse(createdAtStr) ?? DateTime.now();
          if (id.isNotEmpty) {
            _seenOffers[id] = createdAt;
          }
        }

        _notifyNewOffer();

        final firstOffer = freshOffers.first;
        if (firstOffer is Map) {
          final code = firstOffer['orderCode']?.toString() ?? '';
          final origin = firstOffer['originAddress']?.toString() ?? '';
          final dest = (firstOffer['destinations'] as List?)?.isNotEmpty == true
              ? (firstOffer['destinations'] as List).first['address']?.toString() ?? ''
              : firstOffer['destAddress']?.toString() ?? '';
          final price = (double.tryParse(firstOffer['estimatedPrice']?.toString() ?? '') ?? 0).toStringAsFixed(0);
          final orderId = firstOffer['orderId']?.toString() ?? '';

          NotificationService.showNewOfferNotification(
            notificationId: orderId.hashCode,
            orderCode: code,
            originAddress: origin,
            destAddress: dest,
            price: price,
            orderId: orderId,
          ).catchError((e) {
            debugPrint('NOTIFICATION ERROR: $e');
          });
        }

        if (!_offerSheetOpen) {
          _showOfferSheet();
        }
      }

      if (!silent) {
        _showMessage(
          offers.isEmpty ? 'سفارش جدیدی یافت نشد' : '${freshOffers.length} پیشنهاد سفارش دریافت شد',
        );
      }
    } catch (e) {
      debugPrint('REFRESH OFFERS ERROR: $e');
      if (mounted) {
        setState(() => _isFetchingOffers = false);
      }
    }
  }

  void _notifyNewOffer() {
    _audioPlayer.play(AssetSource('sounds/offer_alert.mp3')).then((_) {
      debugPrint('✅ OFFER SOUND PLAYED');
    }).catchError((e) {
      debugPrint('❌ OFFER SOUND ERROR: $e');
    });

    try {
      SystemSound.play(SystemSoundType.alert);
    } catch (_) {}

    try {
      HapticFeedback.heavyImpact();
      HapticFeedback.vibrate();
    } catch (_) {}
  }

  void _showOfferSheet() async {
    if (!mounted || _offerSheetOpen || _offers.isEmpty) return;
    _offerSheetOpen = true;

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        isDismissible: true,
        enableDrag: true,
        backgroundColor: const Color(0xFF111318),
        barrierColor: Colors.black87,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        builder: (sheetContext) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.90,
            minChildSize: 0.55,
            maxChildSize: 0.96,
            builder: (context, scrollController) {
              return SafeArea(
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white30,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                      child: Row(
                        children: [
                          const Icon(Icons.notifications_active, color: AppColors.primaryYellow, size: 26),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${_offers.length} پیشنهاد سفر',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            icon: const Icon(Icons.close, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Colors.white12, height: 1),
                    Expanded(
                      child: _offers.isEmpty
                          ? const Center(
                              child: Text('پیشنهادی وجود ندارد', style: TextStyle(color: Colors.white70)),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              padding: const EdgeInsets.all(14),
                              itemCount: _offers.length,
                              itemBuilder: (context, index) {
                                final raw = _offers[index];
                                if (raw is! Map) return const SizedBox.shrink();
                                final offer = Map<String, dynamic>.from(raw);
                                return _buildOfferCard(offer, sheetContext);
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
    } finally {
      _offerSheetOpen = false;
    }
  }

  void _fitOffersOnMap() {
    if (_offers.isEmpty || !_mapReady) return;

    final points = <LatLng>[];
    if (_currentPosition != null) {
      points.add(_currentPosition!);
    }

    for (final raw in _offers) {
      if (raw is! Map) continue;
      final origin = _readPoint(raw['originLat'], raw['originLng']);
      if (origin != null) points.add(origin);
      final rawDestinations = raw['destinations'];
      if (rawDestinations is List) {
        for (final d in rawDestinations) {
          if (d is! Map) continue;
          final p = _readPoint(d['lat'], d['lng']);
          if (p != null) points.add(p);
        }
      } else {
        final p = _readPoint(raw['destLat'], raw['destLng']);
        if (p != null) points.add(p);
      }
    }

    if (points.length == 1) points.add(_defaultCenter);
    if (points.length < 2) return;

    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.only(top: 130, bottom: 260, left: 40, right: 40),
        ),
      );
    } catch (e) {
      debugPrint('FIT OFFERS ERROR: $e');
    }
  }

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

  // ============================================================
  // RESPOND TO OFFER
  // ============================================================

  Future<void> _respond(
    String offerId,
    String action, {
    Map<String, dynamic>? offerData,
  }) async {
    if (offerId.isEmpty) {
      _showMessage('شناسه پیشنهاد معتبر نیست', isError: true);
      return;
    }

    try {
      final orderId = offerData?['orderId']?.toString() ?? '';
      if (orderId.isNotEmpty) {
        NotificationService.cancelNotification(orderId.hashCode);
      }
    } catch (_) {}

    final result = await DriverService.respondToOffer(
      offerId: offerId,
      driverId: widget.driverId,
      action: action,
    );

    if (!mounted) return;

    if (result['success'] != true) {
      _showMessage(result['message']?.toString() ?? 'عملیات ناموفق بود', isError: true);
      await _refreshOffers(silent: true);
      return;
    }

    setState(() {
      _offers = _offers.where((o) => _offerIdentifier(o) != offerId).toList();
    });

    if (action == 'ACCEPT') {
      await _checkActiveTrips();
      if (!mounted) return;
      if (_activeTrips.isNotEmpty) {
        final latest = _activeTrips.first;
        final orderId = (latest['id'] ?? '').toString();
        if (orderId.isNotEmpty) {
          await _openTripScreen(orderId: orderId, orderData: latest);
        }
      }
    } else {
      _showMessage('پیشنهاد رد شد. منتظر پیشنهادهای جدید باشید...');

      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        await _refreshOffers(silent: true);
      }
    }
  }

  // ============================================================
  // ONLINE / OFFLINE
  // ============================================================

  Future<void> _toggleOnline() async {
    // ✅ اگه مسدود هست، اجازه نده
    if (_isDriverBlocked) {
      _showMessage('حساب شما مسدود است. نمی‌توانید آنلاین شوید.', isError: true);
      return;
    }

    if (_activeTrips.isNotEmpty) {
      _showMessage(
        'شما در حال حاضر ${_activeTrips.length} سفر فعال دارید. تا پایان سفرها نمی‌توانید آفلاین شوید.',
        isError: true,
      );
      return;
    }

    if (_isOnline) {
      setState(() {
        _isOnline = false;
        _offers = [];
      });

      if (_currentPosition != null) {
        await DriverService.updateLocation(
          driverId: widget.driverId,
          lat: _currentPosition!.latitude,
          lng: _currentPosition!.longitude,
          isAvailable: false,
        );
      }

      await DriverService.logOnlineStatus(
        driverId: widget.driverId,
        isOnline: false,
        lat: _currentPosition?.latitude,
        lng: _currentPosition?.longitude,
      );

      _showMessage('آفلاین شدید');
      return;
    }

    if (!_isManualLocation) {
      final position = await LocationService.getCurrentPosition();
      if (!mounted) return;
      if (position != null) {
        _currentPosition = LatLng(position.latitude, position.longitude);
      } else if (_currentPosition == null) {
        _currentPosition = _defaultCenter;
      }
    }

    if (!mounted) return;

    setState(() => _isOnline = true);

    if (_currentPosition != null) {
      await DriverService.updateLocation(
        driverId: widget.driverId,
        lat: _currentPosition!.latitude,
        lng: _currentPosition!.longitude,
        isAvailable: _activeTrips.isEmpty,
      );
    }

    await DriverService.logOnlineStatus(
      driverId: widget.driverId,
      isOnline: true,
      lat: _currentPosition?.latitude,
      lng: _currentPosition?.longitude,
    );

    _showMessage('آنلاین شدید');
    await _refreshOffers(silent: true);
  }

  // ============================================================
  // MANUAL LOCATION
  // ============================================================

  Future<void> _openManualLocationPicker() async {
    if (_isOnline) {
      _showMessage('ابتدا آفلاین شوید تا بتوانید موقعیت را دستی تغییر دهید', isError: true);
      return;
    }

    final picked = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerModal(initialPosition: _currentPosition ?? _defaultCenter),
      ),
    );

    if (picked == null || !mounted) return;

    setState(() {
      _currentPosition = picked;
      _isManualLocation = true;
    });

    _moveMapSafely(picked, 16);

    await DriverService.updateLocation(
      driverId: widget.driverId,
      lat: picked.latitude,
      lng: picked.longitude,
      isAvailable: false,
    );

    if (mounted) _showMessage('موقعیت دستی ثبت شد');
  }

  Future<void> _returnToRealLocation() async {
    setState(() => _isManualLocation = false);
    await _initLocation();
    if (mounted) _showMessage('بازگشت به موقعیت واقعی GPS');
  }

  // ============================================================
  // TEST CONNECTION
  // ============================================================

  Future<void> _testConnection() async {
    if (_loadingTest) return;
    setState(() => _loadingTest = true);

    final results = <Map<String, dynamic>>[];
    bool allOk = true;

    try {
      final health = await DriverService.checkHealth();
      if (health['success'] == true) {
        results.add({'label': 'اینترنت و اتصال به سرور', 'status': 'ok', 'message': 'اتصال برقرار است'});
      } else {
        allOk = false;
        results.add({'label': 'اینترنت و اتصال به سرور', 'status': 'error', 'message': health['message']?.toString() ?? 'اتصال به سرور برقرار نیست. اینترنت را چک کنید.'});
      }
    } catch (e) {
      allOk = false;
      results.add({'label': 'اینترنت و اتصال به سرور', 'status': 'error', 'message': 'خطا در اتصال: $e'});
    }

    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (enabled) {
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          allOk = false;
          results.add({'label': 'سرویس موقعیت مکانی', 'status': 'error', 'message': 'دسترسی به GPS داده نشده. از تنظیمات، دسترسی موقعیت را فعال کنید.'});
        } else {
          final pos = await LocationService.getCurrentPosition();
          if (pos == null) {
            allOk = false;
            results.add({'label': 'سرویس موقعیت مکانی', 'status': 'error', 'message': 'موقعیت فعلی دریافت نشد. GPS را چک کنید.'});
          } else {
            results.add({'label': 'سرویس موقعیت مکانی', 'status': 'ok', 'message': 'موقعیت دریافت شد (${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)})'});
          }
        }
      } else {
        allOk = false;
        results.add({'label': 'سرویس موقعیت مکانی', 'status': 'error', 'message': 'سرویس GPS خاموش است. آن را از تنظیمات گوشی روشن کنید.'});
      }
    } catch (e) {
      allOk = false;
      results.add({'label': 'سرویس موقعیت مکانی', 'status': 'error', 'message': 'خطا در بررسی GPS: $e'});
    }

    try {
      if (_currentPosition != null) {
        final ok = await DriverService.updateLocation(
          driverId: widget.driverId,
          lat: _currentPosition!.latitude,
          lng: _currentPosition!.longitude,
          isAvailable: _isOnline && _activeTrips.isEmpty,
        );
        if (ok) {
          results.add({'label': 'ارسال لوکیشن به سرور', 'status': 'ok', 'message': 'موقعیت شما روی سرور ثبت شد.'});
        } else {
          allOk = false;
          results.add({'label': 'ارسال لوکیشن به سرور', 'status': 'error', 'message': 'ارسال موقعیت به سرور ناموفق بود.'});
        }
      } else {
        results.add({'label': 'ارسال لوکیشن به سرور', 'status': 'warn', 'message': 'موقعیت فعلی برای ارسال موجود نیست.'});
      }
    } catch (e) {
      allOk = false;
      results.add({'label': 'ارسال لوکیشن به سرور', 'status': 'error', 'message': 'خطا در ارسال لوکیشن: $e'});
    }

    if (!mounted) return;
    setState(() => _loadingTest = false);
    _showTestResultDialog(allOk, results);
  }

  void _showTestResultDialog(bool allOk, List<Map<String, dynamic>> results) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF17191D),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: Icon(
            allOk ? Icons.check_circle : Icons.warning_amber_rounded,
            color: allOk ? AppColors.success : Colors.orange,
            size: 54,
          ),
          title: Text(
            allOk ? 'ارتباط سالم است' : 'مشکل در ارتباط',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: results.map((r) {
                final status = r['status']?.toString();
                Color color;
                IconData icon;

                if (status == 'ok') {
                  color = AppColors.success;
                  icon = Icons.check_circle_outline;
                } else if (status == 'error') {
                  color = AppColors.danger;
                  icon = Icons.error_outline;
                } else {
                  color = Colors.orange;
                  icon = Icons.warning_amber_outlined;
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, color: color, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r['label']?.toString() ?? '', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 3),
                            Text(r['message']?.toString() ?? '', style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('باشه', style: TextStyle(color: AppColors.primaryYellow, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // NAVIGATION
  // ============================================================

  void _openWallet() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WalletScreen(driverId: widget.driverId)),
    );
  }

  void _openShifts() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ShiftsScreen(driverId: widget.driverId)),
    );
  }

  void _setActiveNav(String key) {
    setState(() => _activeNav = key);

    if (key != 'home') {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) {
          setState(() => _activeNav = 'home');
        }
      });
    }
  }

  void _showComingSoon(String title) {
    _showMessage('صفحه $title به‌زودی فعال می‌شود');
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.danger : AppColors.success,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ============================================================
  // MAP MARKERS
  // ============================================================

  Marker _offerMapMarker({
    required LatLng point,
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return Marker(
      point: point,
      width: 78,
      height: 34,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0F13),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color, width: 1.4),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 6)],
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
    final carPosition = _currentPosition ?? _defaultCenter;

    markers.add(
      Marker(
        point: carPosition,
        width: 60,
        height: 60,
        child: Container(
          decoration: BoxDecoration(
            color: _isOnline ? AppColors.success : AppColors.danger,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: (_isOnline ? AppColors.success : AppColors.danger).withValues(alpha: 0.5),
                blurRadius: 15,
                spreadRadius: 3,
              ),
            ],
          ),
          child: const Icon(Icons.directions_car, color: Colors.white, size: 30),
        ),
      ),
    );

    if (_offers.isNotEmpty && _activeTrips.isEmpty) {
      for (final raw in _offers) {
        if (raw is! Map) continue;
        final offer = Map<String, dynamic>.from(raw);
        final origin = _readPoint(offer['originLat'], offer['originLng']);

        if (origin != null) {
          markers.add(_offerMapMarker(point: origin, label: 'مبدا', color: AppColors.success, icon: Icons.trip_origin));
        }

        final rawDestinations = offer['destinations'];
        if (rawDestinations is List) {
          for (final d in rawDestinations) {
            if (d is! Map) continue;
            final point = _readPoint(d['lat'], d['lng']);
            if (point == null) continue;
            markers.add(_offerMapMarker(point: point, label: 'مقصد', color: AppColors.danger, icon: Icons.location_on));
          }
        } else {
          final destination = _readPoint(offer['destLat'], offer['destLng']);
          if (destination != null) {
            markers.add(_offerMapMarker(point: destination, label: 'مقصد', color: AppColors.danger, icon: Icons.location_on));
          }
        }
      }
    }
    return markers;
  }

  // ============================================================
  // OFFER CARD
  // ============================================================

  Widget _buildOfferCard(Map<String, dynamic> offer, BuildContext sheetContext) {
    final price = double.tryParse(offer['estimatedPrice']?.toString() ?? '') ?? 0;
    final distanceToPickup = double.tryParse(offer['distanceToPickup']?.toString() ?? '') ?? 0;
    final distance = double.tryParse(offer['estimatedDistance']?.toString() ?? '') ?? 0;
    final origin = _readPoint(offer['originLat'], offer['originLng']);

    final destinations = <Map<String, dynamic>>[];
    final rawDestinations = offer['destinations'];

    if (rawDestinations is List) {
      for (final raw in rawDestinations) {
        if (raw is Map) destinations.add(Map<String, dynamic>.from(raw));
      }
    }

    if (destinations.isEmpty && offer['destAddress'] != null) {
      destinations.add({
        'address': offer['destAddress'],
        'lat': offer['destLat'],
        'lng': offer['destLng'],
      });
    }

    final mapPoints = <LatLng>[];
    if (origin != null) mapPoints.add(origin);
    for (final destination in destinations) {
      final point = _readPoint(destination['lat'], destination['lng']);
      if (point != null) mapPoints.add(point);
    }

    final offerId = _offerIdentifier(offer);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF202329),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primaryYellow.withValues(alpha: 0.55), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 7))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: SizedBox(
              height: 155,
              child: mapPoints.length >= 2
                  ? FlutterMap(
                      options: MapOptions(
                        initialCameraFit: CameraFit.bounds(
                          bounds: LatLngBounds.fromPoints(mapPoints),
                          padding: const EdgeInsets.all(30),
                        ),
                        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.de/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.rahin.driver',
                        ),
                        MarkerLayer(
                          markers: [
                            if (origin != null)
                              _offerMapMarker(point: origin, label: 'مبدا', color: AppColors.success, icon: Icons.trip_origin),
                            ...destinations.map((destination) {
                              final point = _readPoint(destination['lat'], destination['lng']);
                              if (point == null) return null;
                              return _offerMapMarker(point: point, label: 'مقصد', color: AppColors.danger, icon: Icons.location_on);
                            }).whereType<Marker>(),
                          ],
                        ),
                      ],
                    )
                  : Container(
                      color: const Color(0xFF292D34),
                      child: const Center(
                        child: Text('موقعیت سفارش مشخص نشده است', style: TextStyle(color: Colors.white60)),
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.notifications_active, color: AppColors.primaryYellow, size: 23),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('پیشنهاد سفر جدید', style: TextStyle(color: AppColors.primaryYellow, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppColors.primaryYellow.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        '${price.toStringAsFixed(0)} تومان',
                        style: const TextStyle(color: AppColors.primaryYellow, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _offerAddressRow(
                  icon: Icons.trip_origin,
                  color: AppColors.success,
                  title: 'مبدأ',
                  address: offer['originAddress']?.toString() ?? 'مبدأ',
                ),
                const SizedBox(height: 10),
                ...destinations.asMap().entries.map((entry) {
                  final index = entry.key;
                  final destination = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: _offerAddressRow(
                      icon: Icons.location_on,
                      color: AppColors.danger,
                      title: 'مقصد ${index + 1}',
                      address: destination['address']?.toString() ?? 'آدرس مقصد',
                    ),
                  );
                }),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _infoBadge(Icons.route, '${(distance / 1000).toStringAsFixed(1)} کیلومتر'),
                    _infoBadge(Icons.directions_car, '${(distanceToPickup / 1000).toStringAsFixed(1)} کیلومتر تا مبدأ'),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: offerId.isEmpty ? null : () {
                          Navigator.pop(sheetContext);
                          _respond(offerId, 'REJECT', offerData: offer);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.danger.withValues(alpha: 0.15),
                          foregroundColor: AppColors.danger,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('رد پیشنهاد', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: offerId.isEmpty ? null : () {
                          Navigator.pop(sheetContext);
                          _respond(offerId, 'ACCEPT', offerData: offer);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('پذیرش سفر', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _offerAddressRow({required IconData icon, required Color color, required String title, required String address}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 19),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(height: 3),
              Text(address, style: const TextStyle(color: Colors.white, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }

  Widget _infoBadge(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white60, size: 16),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }

  // ============================================================
  // UI HELPERS
  // ============================================================

  Widget _headerCircleButton({required IconData icon, required VoidCallback onTap, Color? bgColor, Color iconColor = Colors.white}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor ?? const Color(0xFF212121).withValues(alpha: 0.95),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Icon(icon, color: iconColor, size: 24),
      ),
    );
  }

  Widget _profileButton() {
    final fullUrl = _resolveAvatarUrl();
    final fallbackLetter = (widget.driverName != null && widget.driverName!.trim().isNotEmpty)
        ? widget.driverName!.trim().characters.first
        : null;

    return GestureDetector(
      onTap: _openProfile,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primaryYellow,
          border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 2),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3))],
          image: (fullUrl != null)
              ? DecorationImage(image: NetworkImage(fullUrl), fit: BoxFit.cover, onError: (_, __) {})
              : null,
        ),
        child: (fullUrl == null)
            ? (fallbackLetter != null
                ? Center(child: Text(fallbackLetter, style: const TextStyle(color: Colors.black, fontSize: 22, fontWeight: FontWeight.bold)))
                : const Icon(Icons.person, color: Colors.black, size: 26))
            : null,
      ),
    );
  }

  Widget _mapCircleButton({required IconData icon, VoidCallback? onTap, bool isLoading = false, Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color ?? const Color(0xFF212121).withValues(alpha: 0.95),
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 10)],
          border: Border.all(color: AppColors.primaryYellow.withValues(alpha: 0.5)),
        ),
        child: isLoading
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryYellow))
            : Icon(icon, color: AppColors.primaryYellow, size: 24),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, String key, {VoidCallback? onTap}) {
    final isActive = _activeNav == key;

    return GestureDetector(
      onTap: () {
        _setActiveNav(key);
        if (onTap != null) onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: isActive ? AppColors.primaryYellow.withValues(alpha: 0.15) : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: isActive ? AppColors.primaryYellow : Colors.white54, size: 22),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isActive ? AppColors.primaryYellow : Colors.white54,
                fontSize: 10,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTripsList() {
    if (_activeTrips.isEmpty) return const SizedBox.shrink();
    final maxHeight = MediaQuery.of(context).size.height * 0.35;

    return Positioned(
      top: _isManualLocation ? 130 : 90,
      left: 16,
      right: 16,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: _activeTrips.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final trip = _activeTrips[index];
            final status = trip['status']?.toString() ?? '';
            final orderCode = trip['orderCode']?.toString() ?? '';
            final destCount = (trip['destinations'] as List?)?.length ?? 0;

            String statusLabel;
            IconData statusIcon;
            Color statusColor;

            switch (status) {
              case 'DRIVER_ASSIGNED':
                statusLabel = 'در حال حرکت به مبدا';
                statusIcon = Icons.navigation;
                statusColor = AppColors.primaryYellow;
                break;
              case 'DRIVER_ARRIVED_PICKUP':
                statusLabel = 'رسیده به مبدا';
                statusIcon = Icons.location_on;
                statusColor = Colors.orange;
                break;
              case 'PICKED_UP':
                statusLabel = 'در حال تحویل';
                statusIcon = Icons.inventory_2;
                statusColor = Colors.green;
                break;
              default:
                statusLabel = status;
                statusIcon = Icons.directions_car;
                statusColor = Colors.white;
            }

            return GestureDetector(
              onTap: () => _openActiveTripByIndex(index),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [BoxShadow(color: AppColors.success.withValues(alpha: 0.3), blurRadius: 16)],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
                      child: Icon(statusIcon, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text('سفر فعال', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('کد: $orderCode', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 2),
                          Text('$destCount مقصد', style: const TextStyle(color: Colors.white60, fontSize: 11)),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCentralButton() {
    final hasActiveTrip = _activeTrips.isNotEmpty;
    final isOnline = _isOnline;

    final ringColor = hasActiveTrip ? Colors.orange : (isOnline ? AppColors.success : Colors.grey.shade700);
    final glowColor = hasActiveTrip ? Colors.orange : (isOnline ? AppColors.success : Colors.transparent);
    final iconColor = hasActiveTrip ? Colors.orange : (isOnline ? AppColors.success : Colors.white70);

    return GestureDetector(
      onTap: _toggleOnline,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF1A1C21),
          border: Border.all(color: ringColor, width: 3),
          boxShadow: [
            if (isOnline && !hasActiveTrip) BoxShadow(color: glowColor.withValues(alpha: 0.6), blurRadius: 24, spreadRadius: 3),
            if (hasActiveTrip) BoxShadow(color: glowColor.withValues(alpha: 0.4), blurRadius: 20, spreadRadius: 2),
            BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 12, offset: const Offset(0, 5)),
          ],
        ),
        child: Icon(hasActiveTrip ? Icons.lock : Icons.power_settings_new, size: 32, color: iconColor),
      ),
    );
  }

  // ============================================================
  // MAIN BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    const double navBarBaseHeight = 76;
    const double centerButtonSize = 68;
    const double centerButtonFloat = 34;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF1E1E1E),
      extendBody: true,
      drawer: Drawer(
        backgroundColor: const Color(0xFF1A1C21),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(24))),
        child: SafeArea(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primaryYellow.withValues(alpha: 0.2), const Color(0xFF1A1C21)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primaryYellow,
                        border: Border.all(color: Colors.white, width: 2),
                        image: (_resolveAvatarUrl() != null)
                            ? DecorationImage(image: NetworkImage(_resolveAvatarUrl()!), fit: BoxFit.cover)
                            : null,
                      ),
                      child: (_resolveAvatarUrl() == null)
                          ? const Icon(Icons.person, color: Colors.black, size: 34)
                          : null,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.driverName ?? 'راننده عزیز',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isOnline ? 'وضعیت: آنلاین' : 'وضعیت: آفلاین',
                      style: TextStyle(color: _isOnline ? AppColors.success : Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  children: [
                    _buildDrawerItem(
                      icon: Icons.person_outline,
                      title: 'پروفایل راننده',
                      onTap: () {
                        Navigator.pop(context);
                        _openProfile();
                      },
                    ),
                    _buildDrawerItem(
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'کیف پول و اعتبار',
                      onTap: () {
                        Navigator.pop(context);
                        _openWallet();
                      },
                    ),
                    _buildDrawerItem(
                      icon: Icons.receipt_long_outlined,
                      title: 'سابقه سفارش‌ها',
                      onTap: () {
                        Navigator.pop(context);
                        _openOrdersHistory();
                      },
                    ),
                    _buildDrawerItem(
                      icon: Icons.calendar_month_outlined,
                      title: 'شیفت‌های کاری',
                      onTap: () {
                        Navigator.pop(context);
                        _openShifts();
                      },
                    ),
                    _buildDrawerItem(
                      icon: Icons.card_giftcard_outlined,
                      title: 'طرح تشویقی',
                      onTap: () {
                        Navigator.pop(context);
                        _showComingSoon('طرح تشویقی');
                      },
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Divider(color: Colors.white12),
                    ),
                    _buildDrawerItem(
                      icon: Icons.support_agent,
                      title: 'پشتیبانی',
                      onTap: () {
                        Navigator.pop(context);
                        _openSupportWeb();
                      },
                    ),
                    _buildDrawerItem(
                      icon: Icons.contact_support_outlined,
                      title: 'تماس با ما',
                      onTap: () {
                        Navigator.pop(context);
                        _openContactWeb();
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: InkWell(
                  onTap: _showLogoutDialog,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.logout, color: AppColors.danger, size: 20),
                        SizedBox(width: 8),
                        Text('خروج از حساب کاربری', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          if (_currentPosition != null)
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentPosition!,
                initialZoom: 15,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                onMapReady: () {
                  if (!mounted) return;
                  setState(() => _mapReady = true);
                  if (_offers.isNotEmpty) _fitOffersOnMap();
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.de/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.rahin.driver',
                  tileProvider: CancellableNetworkTileProvider(),
                ),
                MarkerLayer(markers: _buildMarkers()),
              ],
            )
          else
            const Center(child: CircularProgressIndicator(color: AppColors.primaryYellow)),

          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _headerCircleButton(
                      icon: Icons.menu,
                      onTap: () => _scaffoldKey.currentState?.openDrawer(),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: GestureDetector(
                          onTap: _openWallet,
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF212121).withValues(alpha: 0.95),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.account_balance_wallet, color: AppColors.primaryYellow, size: 20),
                                SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'نمایش اعتبار',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    _profileButton(),
                  ],
                ),
              ),
            ),
          ),

          if (_isManualLocation)
            Positioned(
              top: 90,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(color: AppColors.primaryYellow, borderRadius: BorderRadius.circular(20)),
                  child: const Text(
                    'موقعیت دستی فعال است',
                    style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),

          _buildActiveTripsList(),

          // MAP CONTROLS
          Positioned(
            bottom: navBarBaseHeight + 24,
            right: 16,
            child: Column(
              children: [
                GestureDetector(
                  onTap: _openMessagesScreen,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _mapCircleButton(
                        icon: Icons.mail_outline,
                        onTap: _openMessagesScreen,
                      ),
                      if (_unreadMessagesCount > 0)
                        Positioned(
                          top: -4,
                          right: -4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                            decoration: const BoxDecoration(
                              color: AppColors.danger,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                _unreadMessagesCount > 9 ? '9+' : '$_unreadMessagesCount',
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                _mapCircleButton(
                  icon: _isManualLocation ? Icons.gps_fixed : Icons.my_location,
                  onTap: () {
                    if (_isManualLocation) {
                      _returnToRealLocation();
                    } else if (_currentPosition != null) {
                      _moveMapSafely(_currentPosition!, 16);
                    } else {
                      _initLocation();
                    }
                  },
                ),
                const SizedBox(height: 12),
                Opacity(
                  opacity: _isOnline ? 0.4 : 1,
                  child: _mapCircleButton(
                    icon: Icons.edit_location_alt,
                    onTap: _openManualLocationPicker,
                  ),
                ),
                const SizedBox(height: 12),
                _mapCircleButton(
                  icon: Icons.refresh,
                  isLoading: _isFetchingOffers,
                  onTap: _isFetchingOffers ? null : () => _refreshOffers(silent: false),
                ),
                const SizedBox(height: 12),
                _mapCircleButton(
                  icon: Icons.health_and_safety_outlined,
                  isLoading: _loadingTest,
                  onTap: _loadingTest ? null : _testConnection,
                  color: AppColors.primaryYellow.withValues(alpha: 0.2),
                ),
              ],
            ),
          ),

          if (!_isOnline && _offers.isEmpty && _activeTrips.isEmpty)
            Positioned(
              bottom: navBarBaseHeight + 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E).withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: const Text('برای دریافت سرویس آنلاین شوید', style: TextStyle(color: Colors.white70, fontSize: 14)),
                ),
              ),
            ),

          if (_isOnline && _offers.isEmpty && _activeTrips.isEmpty)
            Positioned(
              bottom: navBarBaseHeight + 16,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () => _refreshOffers(silent: false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E).withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isFetchingOffers)
                          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.success))
                        else
                          const Icon(Icons.refresh, color: AppColors.success, size: 17),
                        const SizedBox(width: 10),
                        Text(
                          _isFetchingOffers ? 'در حال بروزرسانی...' : 'بروزرسانی سفارش‌ها',
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SizedBox(
              height: navBarBaseHeight + centerButtonFloat,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomCenter,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: navBarBaseHeight,
                      decoration: const BoxDecoration(
                        color: Color(0xFF141518),
                        borderRadius: BorderRadius.only(topLeft: Radius.circular(22), topRight: Radius.circular(22)),
                      ),
                      child: SafeArea(
                        top: false,
                        child: Row(
                          children: [
                            Expanded(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  _buildNavItem(Icons.calendar_month, 'شیفت‌ها', 'shifts', onTap: _openShifts),
                                  _buildNavItem(Icons.receipt_long, 'سفارش‌ها', 'orders', onTap: _openOrdersHistory),
                                ],
                              ),
                            ),
                            const SizedBox(width: centerButtonSize + 16),
                            Expanded(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  _buildNavItem(Icons.card_giftcard, 'طرح تشویقی', 'incentive', onTap: () => _showComingSoon('طرح تشویقی')),
                                  _buildNavItem(Icons.home, 'خانه', 'home'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: navBarBaseHeight - (centerButtonSize / 2) - 26,
                    child: _buildCentralButton(),
                  ),
                ],
              ),
            ),
          ),

          // ✅ کاور مسدودی (بالاترین لایه)
          if (_isDriverBlocked)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.92),
                child: SafeArea(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1C21),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.red.withValues(alpha: 0.5), width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.red.withValues(alpha: 0.3),
                                  blurRadius: 30,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.block,
                              color: Colors.red,
                              size: 72,
                            ),
                          ),
                          const SizedBox(height: 32),
                          const Text(
                            'حساب شما مسدود است',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          if (_blockType == 'PERMANENT')
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                              ),
                              child: const Text(
                                'نوع مسدودی: دائم',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          else if (_blockType == 'TEMPORARY')
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                _blockRemainingHours != null
                                    ? 'نوع مسدودی: موقت (${_blockRemainingHours} ساعت باقی‌مانده)'
                                    : 'نوع مسدودی: موقت',
                                style: const TextStyle(
                                  color: Colors.orangeAccent,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          const SizedBox(height: 20),
                          if (_blockReason != null && _blockReason!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF202329),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Column(
                                children: [
                                  const Text(
                                    'دلیل مسدودی:',
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _blockReason!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      height: 1.6,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 32),
                          const Text(
                            'برای رفع مسدودی با پشتیبانی راهین تماس بگیرید',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: () => _openSupportWeb(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryYellow,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.support_agent),
                            label: const Text(
                              'تماس با پشتیبانی',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // DRAWER ITEM
  // ============================================================

  Widget _buildDrawerItem({required IconData icon, required String title, required VoidCallback onTap}) {
    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.primaryYellow.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.primaryYellow, size: 20),
      ),
      title: Text(title, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white30, size: 14),
    );
  }

  // ============================================================
  // SUPPORT & CONTACT
  // ============================================================

  Future<void> _openSupportWeb() async {
    final Uri url = Uri.parse('http://localhost:5173/support');
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        if (mounted) _showMessage('امکان باز کردن لینک پشتیبانی وجود ندارد', isError: true);
      }
    } catch (e) {
      debugPrint('SUPPORT LINK ERROR: $e');
      if (mounted) _showMessage('خطا در باز کردن لینک پشتیبانی', isError: true);
    }
  }

  Future<void> _openContactWeb() async {
    final Uri url = Uri.parse('http://localhost:5173/contact');
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        if (mounted) _showMessage('امکان باز کردن لینک تماس با ما وجود ندارد', isError: true);
      }
    } catch (e) {
      debugPrint('CONTACT LINK ERROR: $e');
      if (mounted) _showMessage('خطا در باز کردن لینک تماس با ما', isError: true);
    }
  }

  // ============================================================
  // LOGOUT
  // ============================================================

  void _showLogoutDialog() {
    Navigator.pop(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF17191D),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: const Icon(Icons.logout, color: AppColors.danger, size: 48),
          title: const Text('خروج از حساب', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17), textAlign: TextAlign.center),
          content: const Text(
            'آیا مطمئن هستید که می‌خواهید از حساب کاربری خود خارج شوید؟',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.spaceEvenly,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              style: TextButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('انصراف', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _logout();
              },
              style: TextButton.styleFrom(
                backgroundColor: AppColors.danger,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('بله، خارج شو', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _logout() async {
    try {
      if (mounted) {
        _showMessage('با موفقیت خارج شدید');
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const SizedBox()),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('LOGOUT ERROR: $e');
      if (mounted) _showMessage('خطا در خروج از حساب', isError: true);
    }
  }
}