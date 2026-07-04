import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/service_locator.dart';
import '../../routing/app_routes.dart';

// 위치 조회 실패 시 대체 좌표 (서울시청).
const _fallbackLocation = LatLng(37.5665, 126.9780);
const _lowAccuracyThresholdMeters = 30.0;

class OutdoorMapScreen extends StatefulWidget {
  const OutdoorMapScreen({super.key});

  @override
  State<OutdoorMapScreen> createState() => _OutdoorMapScreenState();
}

class _OutdoorMapScreenState extends State<OutdoorMapScreen> {
  late final Future<Position?> _positionFuture;

  @override
  void initState() {
    super.initState();
    _positionFuture = _loadPosition();
  }

  Future<Position?> _loadPosition() async {
    try {
      return await getCurrentPosition();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('야외 지도 (GPS 모드)')),
      body: FutureBuilder<Position?>(
        future: _positionFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final position = snapshot.data;
          final center = position == null
              ? _fallbackLocation
              : LatLng(position.latitude, position.longitude);
          final accuracy = position?.accuracy ?? 0;
          final lowAccuracy =
              position == null || accuracy > _lowAccuracyThresholdMeters;
          final markerColor = lowAccuracy ? Colors.amber : Colors.blue;

          return Stack(
            children: [
              FlutterMap(
                options: MapOptions(initialCenter: center, initialZoom: 17),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.navigation.navigation_client',
                  ),
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: center,
                        radius: accuracy > 0 ? accuracy : 20,
                        useRadiusInMeter: true,
                        color: markerColor.withValues(alpha: 0.2),
                        borderColor: markerColor,
                        borderStrokeWidth: 1,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: center,
                        child: Icon(Icons.navigation, color: markerColor),
                      ),
                    ],
                  ),
                ],
              ),
              if (lowAccuracy)
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text('GPS 신호 약함'),
                  ),
                ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: () {
              Navigator.of(context).pushNamed(AppRoutes.indoorMap);
            },
            child: const Text('건물 진입 감지 (임시)'),
          ),
        ),
      ),
    );
  }
}
