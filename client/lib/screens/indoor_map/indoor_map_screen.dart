import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/api_config.dart';
import '../../core/service_locator.dart';
import '../../models/building.dart';
import '../../routing/app_routes.dart';

/// 더현대 서울 실내 지도 SVG 원본. 매장 탭 이벤트는 후순위로 미루고,
/// 지금은 실내 지도 화면에서 이 이미지를 그대로 보여준다.
const _floorMapAsset = 'assets/mock/hyundai_floor_map.svg';

class IndoorMapScreen extends StatefulWidget {
  const IndoorMapScreen({super.key});

  @override
  State<IndoorMapScreen> createState() => _IndoorMapScreenState();
}

class _IndoorMapScreenState extends State<IndoorMapScreen> {
  bool _loading = true;
  Building? _building;
  String? _selectedFloor;

  @override
  void initState() {
    super.initState();
    _loadBuilding();
  }

  Future<void> _loadBuilding() async {
    final building = await buildingRepository.getBuilding(demoBuildingId);
    if (!mounted) return;

    setState(() {
      _building = building;
      _selectedFloor =
          building != null && building.floors.isNotEmpty ? building.floors.first : null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final building = _building;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          building == null
              ? '실내 지도 (PDR 모드)'
              : '${building.name} · $_selectedFloor',
        ),
        actions: [
          if (building != null && building.floors.length > 1)
            PopupMenuButton<String>(
              icon: const Icon(Icons.layers),
              tooltip: '층 전환',
              onSelected: (floor) => setState(() => _selectedFloor = floor),
              itemBuilder: (context) => building.floors
                  .map(
                    (floor) => PopupMenuItem(value: floor, child: Text(floor)),
                  )
                  .toList(),
            ),
        ],
      ),
      body: _loading ? const Center(child: CircularProgressIndicator()) : _buildBody(),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: () {
              Navigator.of(context).pushNamed(AppRoutes.destination);
            },
            child: const Text('목적지 검색'),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_building == null) {
      return const Center(child: Text('건물 정보를 찾을 수 없습니다'));
    }

    return InteractiveViewer(
      maxScale: 6,
      minScale: 0.5,
      child: SvgPicture.asset(_floorMapAsset, fit: BoxFit.contain),
    );
  }
}
