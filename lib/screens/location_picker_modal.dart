import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme/app_theme.dart';

class LocationPickerModal extends StatefulWidget {
  final LatLng initialPosition;
  const LocationPickerModal({super.key, required this.initialPosition});

  @override
  State<LocationPickerModal> createState() => _LocationPickerModalState();
}

class _LocationPickerModalState extends State<LocationPickerModal> {
  late LatLng _selected;
  final MapController _controller = MapController();

  @override
  void initState() {
    super.initState();
    _selected = widget.initialPosition;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('انتخاب دستی موقعیت'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _selected),
            child: const Text('تایید', style: TextStyle(color: AppColors.primaryYellow, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCenter: widget.initialPosition,
              initialZoom: 15,
              onTap: (_, point) {
                setState(() => _selected = point);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.de/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.rahin.driver',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _selected,
                    width: 60, height: 60,
                    child: const Icon(Icons.location_on, color: AppColors.primaryYellow, size: 50),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            top: 12, left: 16, right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'روی نقشه ضربه بزنید تا موقعیت خود را دقیق انتخاب کنید',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}